// StreamingEngine.swift
// DisplayPADMac
//
// Capture l'écran via ScreenCaptureKit et encode les frames en H.264
// avec VideoToolbox. Les sections nécessitant des entitlements ou des
// autorisations système sont commentées avec des instructions claires.
//
// ENTITLEMENTS REQUIS dans le profil de signature :
//   - com.apple.security.screen-capture (ScreenCaptureKit)
//   - com.apple.security.network.client (connexion réseau sortante)
//
// PERMISSION REQUISE dans Info.plist :
//   - NSScreenCaptureUsageDescription

import Foundation
import CoreMedia
import CoreVideo

// MARK: - Imports conditionnels (frameworks nécessitant entitlements)
// Ces imports fonctionnent à la compilation ; les API échouent à l'exécution
// sans l'autorisation système accordée par l'utilisateur.
import ScreenCaptureKit
import VideoToolbox

// MARK: - Protocole délégué

/// Le délégué reçoit les frames H.264 encodées prêtes à être envoyées.
protocol StreamingEngineDelegate: AnyObject {
    /// Appelé sur un thread arbitraire avec les données NAL H.264 d'une frame.
    func didEncodeFrame(data: Data)
}

// MARK: - StreamingEngine

/// Moteur de capture d'écran et d'encodage H.264 temps réel.
@MainActor
class StreamingEngine: NSObject, ObservableObject {

    // MARK: Propriétés publiques

    weak var delegate: StreamingEngineDelegate?

    @Published var isCapturing: Bool = false
    @Published var measuredFPS: Double = 0.0

    // MARK: Propriétés privées

    /// Session d'encodage VideoToolbox
    private var compressionSession: VTCompressionSession?

    /// Stream ScreenCaptureKit
    private var scStream: SCStream?

    /// File de traitement des frames
    private let encodeQueue = DispatchQueue(label: "com.displaypad.encode", qos: .userInteractive)

    /// Compteur de frames pour le calcul du FPS réel
    private var frameCounter: Int = 0
    private var fpsTimer: Timer?
    private var captureStartDate = Date()

    // MARK: - Démarrage de la capture

    /// Démarre la capture de l'écran spécifié avec les paramètres fournis.
    /// - Parameters:
    ///   - displayID: Identifiant CGDirectDisplayID de l'écran à capturer.
    ///   - settings: Paramètres de l'application (résolution, FPS, qualité, profil H.264).
    func startCapture(displayID: CGDirectDisplayID = CGMainDisplayID(), settings: AppSettings) {
        guard !isCapturing else {
            print("[StreamingEngine] Capture déjà en cours")
            return
        }

        // ── 1. Configurer la session d'encodage VideoToolbox ──────────────────
        setupCompressionSession(settings: settings)

        // ── 2. Configurer et démarrer le SCStream ──────────────────────────────
        // ⚠️ Nécessite l'autorisation de capture d'écran accordée par l'utilisateur
        // (boîte de dialogue système), ET l'entitlement com.apple.security.screen-capture.
        Task {
            await setupScreenCapture(displayID: displayID, settings: settings)
        }

        // ── 3. Timer de calcul FPS réel ────────────────────────────────────────
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.measuredFPS = Double(self.frameCounter)
                self.frameCounter = 0
            }
        }

        isCapturing = true
        captureStartDate = Date()
        print("[StreamingEngine] Capture démarrée — \(settings.actualWidth)×\(settings.actualHeight) @ \(settings.actualFPS) fps")
    }

    // MARK: - Arrêt de la capture

    func stopCapture() {
        guard isCapturing else { return }

        // Arrêt du SCStream
        if let stream = scStream {
            Task {
                do {
                    try await stream.stopCapture()
                } catch {
                    print("[StreamingEngine] Erreur arrêt capture : \(error)")
                }
            }
            scStream = nil
        }

        // Libération de la session VideoToolbox
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }

        fpsTimer?.invalidate()
        fpsTimer = nil
        isCapturing = false
        measuredFPS = 0.0
        print("[StreamingEngine] Capture arrêtée")
    }

    // MARK: - Configuration VideoToolbox

    private func setupCompressionSession(settings: AppSettings) {
        let width  = settings.actualWidth
        let height = settings.actualHeight
        let fps    = settings.actualFPS
        let bitrate = settings.actualBitrate

        // Profil H.264 : Baseline recommandé pour iPad Air 1 (faible puissance de décodage)
        let profileLevel: CFString
        switch settings.h264Profile {
        case .baseline: profileLevel = kVTProfileLevel_H264_Baseline_AutoLevel
        case .main:     profileLevel = kVTProfileLevel_H264_Main_AutoLevel
        case .high:     profileLevel = kVTProfileLevel_H264_High_AutoLevel
        }

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator:                      nil,
            width:                          Int32(width),
            height:                         Int32(height),
            codecType:                      kCMVideoCodecType_H264,
            encoderSpecification:           nil,
            imageBufferAttributes:          nil,
            compressedDataAllocator:        nil,
            outputCallback:                 compressionOutputCallback,
            refcon:                         Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut:          &session
        )
        guard status == noErr, let session else {
            print("[StreamingEngine] Échec création VTCompressionSession : \(status)")
            return
        }

        // ── Propriétés d'encodage ─────────────────────────────────────────────

        // Temps réel (faible latence)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        // Profil H.264
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profileLevel)

        // Bitrate moyen
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: NSNumber(value: bitrate))

        // FPS cible
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                             value: NSNumber(value: fps))

        // Pas de B-frames (faible latence, compatibilité iPad Air 1)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                             value: kCFBooleanFalse)

        // IDR toutes les ~60 frames (~2s à 30fps)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: NSNumber(value: 60))

        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session
        print("[StreamingEngine] VTCompressionSession configurée — profil=\(settings.h264Profile.label) bitrate=\(bitrate/1_000_000)Mbps")
    }

    // MARK: - Configuration ScreenCaptureKit

    private func setupScreenCapture(displayID: CGDirectDisplayID, settings: AppSettings) async {
        // ⚠️ ENTITLEMENT REQUIS : com.apple.security.screen-capture
        // ⚠️ Boîte de dialogue utilisateur requise au premier lancement

        do {
            // Récupère la liste des contenus capturables
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                               onScreenWindowsOnly: true)
            // Trouve l'écran cible
            guard let display = content.displays.first(where: { $0.displayID == displayID })
                             ?? content.displays.first else {
                print("[StreamingEngine] Écran introuvable (ID: \(displayID))")
                return
            }

            // Filtre : capture tout l'écran (pas d'exclusion pour l'instant)
            let filter = SCContentFilter(display: display, excludingWindows: [])

            // Configuration de la stream
            let config = SCStreamConfiguration()
            config.width  = settings.actualWidth
            config.height = settings.actualHeight
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.actualFPS))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false // Pas de curseur en v0.1

            let stream = SCStream(filter: filter, configuration: config, delegate: self)

            // Ajoute le handler de sortie vidéo sur la file d'encodage
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: encodeQueue)
            try await stream.startCapture()

            await MainActor.run { self.scStream = stream }
            print("[StreamingEngine] SCStream démarrée")

        } catch {
            print("[StreamingEngine] Erreur démarrage SCStream : \(error)")
            // Affiche le message d'erreur approprié selon le type
            if (error as NSError).domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" {
                print("[StreamingEngine] → Vérifiez que l'autorisation de capture d'écran est accordée dans Préférences Système > Confidentialité et sécurité > Enregistrement d'écran")
            }
        }
    }

    // MARK: - Callback d'encodage VideoToolbox (C function pointer)

    /// Callback C appelé par VideoToolbox pour chaque frame encodée.
    /// Doit être une fonction globale (pas une closure) pour être passée en tant que pointeur.
    private let compressionOutputCallback: VTCompressionOutputCallback = { refcon, _, status, flags, sampleBuffer in
        guard status == noErr,
              let sampleBuffer,
              let refcon else { return }

        // Évite le retain cycle : on utilise unretained pour l'appel
        let engine = Unmanaged<StreamingEngine>.fromOpaque(refcon).takeUnretainedValue()
        engine.handleEncodedFrame(sampleBuffer: sampleBuffer, flags: flags)
    }

    /// Traite une frame H.264 encodée : extrait les NAL units et appelle le délégué.
    private func handleEncodedFrame(sampleBuffer: CMSampleBuffer, flags: VTEncodeInfoFlags) {
        // Vérifie si c'est une IDR frame (I-frame, keyframe)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[CFString: Any]]
        let isKeyFrame = attachments?.first?[kCMSampleAttachmentKey_NotSync as CFString] == nil

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let result = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0,
                                                 lengthAtOffsetOut: nil,
                                                 totalLengthOut: &totalLength,
                                                 dataPointerOut: &dataPointer)
        guard result == kCMBlockBufferNoErr, let pointer = dataPointer else { return }

        // Conversion Avcc → AnnexB (ajout des start codes 0x00 0x00 0x00 0x01)
        var annexBData = Data()

        if isKeyFrame {
            // Ajoute SPS et PPS depuis le format de description
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                appendParameterSets(from: formatDescription, to: &annexBData)
            }
        }

        // Parse les NALU en format AVCC (longueur sur 4 octets + données)
        var offset = 0
        while offset < totalLength {
            guard offset + 4 <= totalLength else { break }
            var naluLength: UInt32 = 0
            memcpy(&naluLength, pointer.advanced(by: offset), 4)
            naluLength = CFSwapInt32BigToHost(naluLength)

            offset += 4
            guard offset + Int(naluLength) <= totalLength else { break }

            // Start code AnnexB
            annexBData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            annexBData.append(Data(bytes: pointer.advanced(by: offset), count: Int(naluLength)))
            offset += Int(naluLength)
        }

        frameCounter += 1
        delegate?.didEncodeFrame(data: annexBData)
    }

    /// Ajoute les SPS et PPS (parameter sets) au format AnnexB.
    private func appendParameterSets(from description: CMFormatDescription, to data: inout Data) {
        var parameterSetCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0,
                                                           parameterSetPointerOut: nil,
                                                           parameterSetSizeOut: nil,
                                                           parameterSetCountOut: &parameterSetCount,
                                                           nalUnitHeaderLengthOut: nil)
        for i in 0..<parameterSetCount {
            var paramSet: UnsafePointer<UInt8>?
            var paramSetSize = 0
            let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                description,
                parameterSetIndex: i,
                parameterSetPointerOut: &paramSet,
                parameterSetSizeOut: &paramSetSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            if status == noErr, let ps = paramSet {
                data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                data.append(Data(bytes: ps, count: paramSetSize))
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension StreamingEngine: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[StreamingEngine] Stream arrêté avec erreur : \(error)")
        Task { @MainActor in
            self.isCapturing = false
        }
    }
}

// MARK: - SCStreamOutput

extension StreamingEngine: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }

        // Encode la frame si la session est disponible
        Task { @MainActor in
            guard let session = compressionSession,
                  let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let duration = CMSampleBufferGetDuration(sampleBuffer)

            VTCompressionSessionEncodeFrame(session,
                                            imageBuffer: imageBuffer,
                                            presentationTimeStamp: presentationTime,
                                            duration: duration,
                                            frameProperties: nil,
                                            sourceFrameRefcon: nil,
                                            infoFlagsOut: nil)
        }
    }
}
