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

    /// Connexion NWConnection (framework Network)
    private var connection: NWConnection?

    /// Timer de ping (toutes les 5 secondes)
    private var pingTimer: Timer?

    /// Port TCP configuré
    private var currentPort: Int = 7000

    /// Date du dernier ping envoyé (pour mesurer la latence)
    private var lastPingDate: Date?

    // MARK: - Interface publique

    /// Établit la connexion TCP vers 127.0.0.1:port
    func connect(port: Int = 7100) {
        isUserInitiatedDisconnect = false
        stopReconnectTimer()
        startConnectionAttempt(port: port)
    }

    private func startConnectionAttempt(port: Int) {
        guard !isConnected else { return }
        currentPort = port

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        DispatchQueue.main.async { [weak self] in
            self?.isConnecting = true
        }

        let host = NWEndpoint.Host("127.0.0.1")
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            print("[ConnectionManager] Port invalide : \(port)")
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 2
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: host, port: nwPort, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state)
        }
        connection = conn
        conn.start(queue: networkQueue)
    }

    /// Ferme la connexion volontairement
    func disconnect() {
        isUserInitiatedDisconnect = true
        stopReconnectTimer()
        sendPacket(type: .disconnect, payload: Data())
        stopPingTimer()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
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

    /// Envoie un frame H.264 encodé
    func sendFrame(_ frameData: Data) {
        sendPacket(type: .frame, payload: frameData)
    }

    // MARK: - Gestion de la connexion

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            print("[ConnectionManager] Connexion établie sur le port \(currentPort)")
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
            } else {
                self.startConnectionAttempt(port: self.currentPort)
            }
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}
