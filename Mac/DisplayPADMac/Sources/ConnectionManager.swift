// ConnectionManager.swift
// DisplayPADMac
//
// Gère la connexion TCP/USB vers l'iPad via usbmuxd (iproxy).
// Implémente le protocole binaire DPHeader défini dans Shared/Protocol.h.
// Toutes les valeurs réseau sont en big-endian.

import Foundation
import Network

// MARK: - Protocole binaire (miroir de Shared/Protocol.h)

/// Types de paquets du protocole DisplayPAD
enum DPPacketType: UInt32 {
    case hello       = 0x01
    case helloAck    = 0x02
    case config      = 0x03
    case configAck   = 0x04
    case frame       = 0x05
    case ping        = 0x06
    case pong        = 0x07
    case disconnect  = 0x08
}

/// En-tête du protocole binaire (12 octets, big-endian)
struct DPHeader {
    static let magic: UInt32 = 0x44505044  // "DPPD"
    static let size: Int = 12              // 3 × UInt32

    let type: UInt32
    let length: UInt32  // longueur du payload qui suit

    /// Sérialise l'en-tête en Data (big-endian)
    func toData() -> Data {
        var data = Data(capacity: DPHeader.size)
        var magic  = CFSwapInt32HostToBig(DPHeader.magic)
        var type_  = CFSwapInt32HostToBig(self.type)
        var length = CFSwapInt32HostToBig(self.length)
        withUnsafeBytes(of: &magic)  { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &type_)  { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        return data
    }

    /// Désérialise depuis Data (big-endian)
    static func from(data: Data) -> DPHeader? {
        guard data.count >= DPHeader.size else { return nil }
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let type  = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let len   = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }
        guard CFSwapInt32BigToHost(magic) == DPHeader.magic else { return nil }
        return DPHeader(type: CFSwapInt32BigToHost(type), length: CFSwapInt32BigToHost(len))
    }
}

/// Payload CONFIG (5 × UInt32, big-endian)
struct DPConfigPayload {
    let width: UInt32
    let height: UInt32
    let fps: UInt32
    let bitrate: UInt32
    let orientation: UInt32  // 0 = paysage, 1 = portrait

    func toData() -> Data {
        var data = Data(capacity: 20)
        var w = CFSwapInt32HostToBig(width)
        var h = CFSwapInt32HostToBig(height)
        var f = CFSwapInt32HostToBig(fps)
        var b = CFSwapInt32HostToBig(bitrate)
        var o = CFSwapInt32HostToBig(orientation)
        withUnsafeBytes(of: &w) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &f) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &b) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &o) { data.append(contentsOf: $0) }
        return data
    }
}

/// Payload HELLO (2 octets version + 64 octets nom de device)
struct DPHelloPayload {
    static let deviceNameLength = 64

    let versionMajor: UInt8
    let versionMinor: UInt8
    let deviceName: String

    func toData() -> Data {
        var data = Data(capacity: 2 + DPHelloPayload.deviceNameLength)
        data.append(versionMajor)
        data.append(versionMinor)
        // Nom du device sur 64 octets, padé avec des zéros
        var nameBytes = Array(deviceName.utf8.prefix(DPHelloPayload.deviceNameLength))
        while nameBytes.count < DPHelloPayload.deviceNameLength {
            nameBytes.append(0)
        }
        data.append(contentsOf: nameBytes)
        return data
    }
}

// MARK: - ConnectionManager

/// Gère la connexion TCP vers l'iPad via iproxy (usbmuxd).
class ConnectionManager: ObservableObject {

    // MARK: État publié

    @Published var isConnected: Bool = false
    @Published var deviceName: String = ""
    @Published var currentFPS: Double = 0.0
    @Published var currentBitrate: Double = 0.0
    @Published var batteryLevel: Int = -1
    @Published var currentLatency: Double = 0.0
    @Published var isConnecting: Bool = false

    /// Active ou désactive la tentative continue de reconnexion automatique
    var autoReconnectEnabled: Bool = true

    /// Indique si la déconnexion a été volontairement demandée par l'utilisateur
    private var isUserInitiatedDisconnect: Bool = false

    /// Timer de reconnexion périodique
    private var reconnectTimer: Timer?

    // MARK: Callbacks de session (appelés sur le thread principal)

    /// L'iPad a accepté le HELLO : on peut envoyer la configuration.
    var onHelloAck: (() -> Void)?
    /// L'iPad a accepté la CONFIG : on peut démarrer le flux vidéo.
    var onConfigAck: (() -> Void)?
    /// La connexion est perdue ou fermée.
    var onDisconnected: (() -> Void)?

    // MARK: Propriétés privées

    /// File d'attente réseau dédiée
    private let networkQueue = DispatchQueue(label: "com.displaypad.network", qos: .userInitiated)

    /// Connexion NWConnection TCP (contrôle + mode USB)
    private var connection: NWConnection?

    /// Connexion NWConnection UDP (flux vidéo Wi-Fi ultra-basse latence sur port 7001)
    private var udpConnection: NWConnection?

    /// Navigateur Bonjour / AWDL pour découverte Peer-to-Peer
    private var browser: NWBrowser?

    /// Indique si la session actuelle est en mode Peer-to-Peer (AWDL)
    private var isPeerToPeerMode: Bool = false

    /// Compteur séquentiel d'image UDP
    private var udpFrameId: UInt32 = 0

    /// Timer de ping (toutes les 5 secondes)
    private var pingTimer: Timer?

    /// Hôte TCP configuré (127.0.0.1 pour USB, IP directe pour Wi-Fi)
    private var currentHost: String = "127.0.0.1"

    /// Port TCP configuré
    private var currentPort: Int = 7000

    /// Date du dernier ping envoyé (pour mesurer la latence)
    private var lastPingDate: Date?

    /// Contrôle de congestion (backpressure) pour éviter le bufferbloat en Wi-Fi
    private let inflightLock = NSLock()
    private var _inFlightFrames: Int = 0

    /// Indique si le réseau peut absorber une nouvelle frame sans accumuler de latence
    nonisolated var canSendFrame: Bool {
        inflightLock.lock()
        defer { inflightLock.unlock() }
        return _inFlightFrames < 2
    }

    // MARK: - Interface publique

    /// Découvre et connecte l'iPad en Wi-Fi Direct (AWDL / Bonjour) tout en conservant internet
    func connectPeerToPeer() {
        isUserInitiatedDisconnect = false
        isPeerToPeerMode = true
        stopReconnectTimer()
        startPeerToPeerDiscovery()
    }

    private func startPeerToPeerDiscovery() {
        guard !isConnected else { return }
        currentHost = "awdl"

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        udpConnection?.cancel()
        udpConnection = nil
        browser?.cancel()
        browser = nil
        udpFrameId = 0

        DispatchQueue.main.async { [weak self] in
            self?.isConnecting = true
        }

        let params = NWParameters()
        params.includePeerToPeer = true
        let nwBrowser = NWBrowser(for: .bonjour(type: "_displaypad._tcp", domain: nil), using: params)

        var fallbackWorkItem: DispatchWorkItem?

        nwBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self, !self.isConnected, self.connection == nil else { return }

            // 1. Si l'interface directe awdl0 est prête, on l'utilise immédiatement !
            if let awdlResult = results.first(where: { $0.interfaces.contains(where: { $0.name == "awdl0" }) }) {
                fallbackWorkItem?.cancel()
                fallbackWorkItem = nil
                print("[AWDL] Interface directe awdl0 trouvée : \(awdlResult.endpoint)")
                self.browser?.cancel()
                self.browser = nil
                self.connectToEndpoint(awdlResult.endpoint, requiredInterface: awdlResult.interfaces.first(where: { $0.name == "awdl0" }))
                return
            }

            // 2. Sinon, on attend 1.5s que awdl0 s'initialise avant de se rabattre sur en0
            if fallbackWorkItem == nil, let anyResult = results.first {
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self, !self.isConnected, self.connection == nil else { return }
                    let ifNames = anyResult.interfaces.map { $0.name }.joined(separator: ",")
                    print("[AWDL] awdl0 indisponible après 1.5s, repli sur : \(anyResult.endpoint) (\(ifNames))")
                    self.browser?.cancel()
                    self.browser = nil
                    self.connectToEndpoint(anyResult.endpoint, requiredInterface: nil)
                }
                fallbackWorkItem = item
                self.networkQueue.asyncAfter(deadline: .now() + 1.5, execute: item)
            }
        }

        nwBrowser.stateUpdateHandler = { state in
            print("[AWDL] État du navigateur Bonjour : \(state)")
        }

        browser = nwBrowser
        nwBrowser.start(queue: networkQueue)
        print("[AWDL] Recherche Peer-to-Peer (_displaypad._tcp) démarrée…")
    }

    private func connectToEndpoint(_ endpoint: NWEndpoint, requiredInterface: NWInterface?) {
        inflightLock.lock()
        _inFlightFrames = 0
        inflightLock.unlock()

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 4
        tcpOptions.enableKeepalive = true
        tcpOptions.noDelay = true

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true

        let conn = NWConnection(to: endpoint, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state)
        }
        connection = conn
        conn.start(queue: networkQueue)
    }

    /// Établit la connexion TCP (+ UDP en Wi-Fi) vers host:port
    func connect(host: String = "127.0.0.1", port: Int = 7100) {
        isUserInitiatedDisconnect = false
        isPeerToPeerMode = false
        browser?.cancel()
        browser = nil
        stopReconnectTimer()
        startConnectionAttempt(host: host, port: port)
    }

    private func startConnectionAttempt(host: String, port: Int) {
        guard !isConnected else { return }
        currentHost = host
        currentPort = port

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        udpConnection?.cancel()
        udpConnection = nil
        udpFrameId = 0

        DispatchQueue.main.async { [weak self] in
            self?.isConnecting = true
        }

        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            print("[ConnectionManager] Port invalide : \(port)")
            return
        }

        inflightLock.lock()
        _inFlightFrames = 0
        inflightLock.unlock()

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 3
        tcpOptions.enableKeepalive = true
        tcpOptions.noDelay = true // Désactive Nagle pour une latence minimale en Wi-Fi
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state)
        }
        connection = conn
        conn.start(queue: networkQueue)

        // En mode Wi-Fi (hôte non-localhost), ouvrir le canal vidéo UDP port 7001
        if host != "127.0.0.1", let udpPort = NWEndpoint.Port(rawValue: 7001) {
            let udp = NWConnection(host: nwHost, port: udpPort, using: .udp)
            udp.start(queue: networkQueue)
            udpConnection = udp
            print("[ConnectionManager] Canal vidéo UDP ouvert vers \(host):7001")
        }
    }

    /// Ferme la connexion volontairement
    func disconnect() {
        isUserInitiatedDisconnect = true
        stopReconnectTimer()
        browser?.cancel()
        browser = nil
        sendPacket(type: .disconnect, payload: Data())
        stopPingTimer()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        udpConnection?.cancel()
        udpConnection = nil
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.isConnecting = false
            self?.deviceName = ""
            self?.currentFPS = 0
            self?.currentBitrate = 0
            self?.currentLatency = 0
            self?.batteryLevel = -1
            self?.onDisconnected?()
        }
    }

    /// Envoie la configuration courante à l'iPad
    func sendConfig(settings: AppSettings) {
        let payload = DPConfigPayload(
            width:       UInt32(settings.actualWidth),
            height:      UInt32(settings.actualHeight),
            fps:         UInt32(settings.actualFPS),
            bitrate:     UInt32(settings.actualBitrate),
            orientation: settings.orientation.protocolValue
        )
        sendPacket(type: .config, payload: payload.toData())
    }

    /// Envoie un paquet HELLO avec la version du protocole et le nom du Mac
    func sendHello() {
        let macName = Host.current().localizedName ?? "MacBook"
        let hello = DPHelloPayload(
            versionMajor: 0,
            versionMinor: 1,
            deviceName: macName
        )
        sendPacket(type: .hello, payload: hello.toData())
    }

    /// Envoie un PING et mesure la latence
    func ping() {
        lastPingDate = Date()
        sendPacket(type: .ping, payload: Data())
    }

    /// Envoie un frame H.264 encodé via TCP (noDelay + backpressure strict pour zéro perte H.264 et zéro retard)
    func sendFrame(_ frameData: Data) {
        // TCP avec backpressure (_inFlightFrames < 2) évite à la fois la perte de P-frames (UDP)
        // et l'accumulation de buffer (bufferbloat).
        inflightLock.lock()
        _inFlightFrames += 1
        inflightLock.unlock()

        let header = DPHeader(type: DPPacketType.frame.rawValue, length: UInt32(frameData.count))
        var packet = header.toData()
        packet.append(frameData)
        connection?.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let self = self {
                self.inflightLock.lock()
                self._inFlightFrames = max(0, self._inFlightFrames - 1)
                self.inflightLock.unlock()
            }
            if let error = error {
                print("[ConnectionManager] Erreur envoi frame : \(error)")
            }
        })
    }

    // MARK: - Gestion de la connexion

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            print("[ConnectionManager] Connexion établie sur le port \(currentPort)")
            if isPeerToPeerMode, let endpoint = connection?.currentPath?.remoteEndpoint,
               case let .hostPort(remoteHost, _) = endpoint,
               let udpPort = NWEndpoint.Port(rawValue: 7001) {
                let udpParams = NWParameters.udp
                udpParams.includePeerToPeer = true
                let udp = NWConnection(host: remoteHost, port: udpPort, using: udpParams)
                udp.start(queue: networkQueue)
                udpConnection = udp
                print("[AWDL] Canal vidéo UDP ouvert vers \(remoteHost):7001")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.stopReconnectTimer()
                self.isConnecting = false
                self.isConnected = true
                self.deviceName = "iPad Air"
            }
            sendHello()
            startPingTimer()
            startReceiving()

        case .failed(let error):
            print("[ConnectionManager] Tentative de connexion au port \(currentPort) : \(error.localizedDescription)")
            handleDisconnect()

        case .cancelled:
            print("[ConnectionManager] Connexion fermée")

        case .waiting(let error):
            print("[ConnectionManager] En attente de l'iPad : \(error.localizedDescription)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if self?.isConnected == false {
                    self?.handleDisconnect()
                }
            }

        default:
            break
        }
    }

    // MARK: - Réception de paquets

    private func startReceiving() {
        receiveHeader()
    }

    /// Lit l'en-tête DPHeader (12 octets)
    private func receiveHeader() {
        connection?.receive(minimumIncompleteLength: DPHeader.size,
                            maximumLength: DPHeader.size) { [weak self] data, _, isComplete, error in
            if let error = error {
                print("[ConnectionManager] Erreur réception en-tête : \(error)")
                self?.handleDisconnect()
                return
            }
            guard let data = data, let header = DPHeader.from(data: data) else {
                self?.receiveHeader()
                return
            }
            if header.length > 0 {
                self?.receivePayload(header: header)
            } else {
                self?.handlePacket(header: header, payload: Data())
                self?.receiveHeader()
            }
        }
    }

    /// Lit le payload du paquet après l'en-tête
    private func receivePayload(header: DPHeader) {
        let length = Int(header.length)
        connection?.receive(minimumIncompleteLength: length,
                            maximumLength: length) { [weak self] data, _, _, error in
            if let error = error {
                print("[ConnectionManager] Erreur réception payload : \(error)")
                self?.handleDisconnect()
                return
            }
            self?.handlePacket(header: header, payload: data ?? Data())
            self?.receiveHeader()
        }
    }

    /// Traite un paquet reçu
    private func handlePacket(header: DPHeader, payload: Data) {
        guard let type = DPPacketType(rawValue: header.type) else {
            print("[ConnectionManager] Type de paquet inconnu : \(header.type)")
            return
        }
        switch type {
        case .pong:
            if let date = lastPingDate {
                let latency = Date().timeIntervalSince(date) * 1000
            DispatchQueue.main.async { [weak self] in self?.currentLatency = latency }
                print("[ConnectionManager] PONG reçu, latence : \(String(format: "%.1f", latency)) ms")
            }
        case .helloAck:
            print("[ConnectionManager] HELLO_ACK reçu — iPad prêt")
            DispatchQueue.main.async { [weak self] in self?.onHelloAck?() }
        case .configAck:
            print("[ConnectionManager] CONFIG_ACK reçu — configuration acceptée")
            DispatchQueue.main.async { [weak self] in self?.onConfigAck?() }
        default:
            print("[ConnectionManager] Paquet reçu : type=\(type)")
        }
    }

    // MARK: - Envoi de paquets

    private func sendPacket(type: DPPacketType, payload: Data) {
        let header = DPHeader(type: type.rawValue, length: UInt32(payload.count))
        var packet = header.toData()
        packet.append(payload)
        connection?.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("[ConnectionManager] Erreur envoi : \(error)")
            }
        })
    }

    // MARK: - Timer de ping

    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.ping()
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    // MARK: - Gestion de la déconnexion inattendue

    private func handleDisconnect() {
        stopPingTimer()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        udpConnection?.cancel()
        udpConnection = nil

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.deviceName = ""
            self.currentFPS = 0
            self.currentBitrate = 0
            self.currentLatency = 0
            self.onDisconnected?()

            if self.autoReconnectEnabled && !self.isUserInitiatedDisconnect {
                self.scheduleReconnect()
            } else {
                self.isConnecting = false
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectTimer == nil, !isConnected, !isUserInitiatedDisconnect else { return }
        isConnecting = true
        print("[ConnectionManager] Reconnexion automatique dans 1.5s...")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isConnected || self.isUserInitiatedDisconnect {
                self.stopReconnectTimer()
            } else if self.isPeerToPeerMode {
                self.startPeerToPeerDiscovery()
            } else {
                self.startConnectionAttempt(host: self.currentHost, port: self.currentPort)
            }
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}
