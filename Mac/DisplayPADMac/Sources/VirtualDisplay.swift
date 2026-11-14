// VirtualDisplay.swift
// DisplayPADMac
//
// Création d'un écran virtuel via les classes privées CGVirtualDisplay
// (CoreGraphics, macOS 11+). L'écran apparaît dans Réglages > Moniteurs et
// peut être ciblé par ScreenCaptureKit.
//
// RISQUES : API privée (peut changer), incompatible Mac App Store.

import CoreGraphics
import Foundation
import CGVirtualDisplayBridge

final class VirtualDisplayManager {

    /// Identifiant de l'écran virtuel créé (nil si non créé)
    private(set) var virtualDisplayID: CGDirectDisplayID?

    /// Référence forte : l'écran disparaît quand l'objet est libéré.
    private var display: CGVirtualDisplay?

    deinit { destroyVirtualDisplay() }

    /// Crée un écran virtuel.
    /// - Parameters:
    ///   - width/height: résolution en pixels (ex: 2048×1536 pour iPad Air 1)
    ///   - ppi: densité de pixels (264 pour iPad Air 1 Retina)
    ///   - hiDPI: active le mode Retina (le système voit width/2 × height/2 en points)
    func createVirtualDisplay(width: UInt32, height: UInt32, ppi: UInt32, hiDPI: Bool = false,
                              refreshRate: Double = 60) -> CGDirectDisplayID? {
        if let id = virtualDisplayID { return id }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = "DisplayPAD"
        descriptor.vendorID = 0x5678
        descriptor.productID = 0x1234
        descriptor.serialNum = 0x0001
        descriptor.maxPixelsWide = width
        descriptor.maxPixelsHigh = height
        // Taille physique en mm : pixels / ppi * 25.4
        descriptor.sizeInMillimeters = CGSize(
            width: Double(width) / Double(max(ppi, 1)) * 25.4,
            height: Double(height) / Double(max(ppi, 1)) * 25.4)
        // Primaires sRGB
        descriptor.redPrimary = CGPoint(x: 0.64, y: 0.33)
        descriptor.greenPrimary = CGPoint(x: 0.30, y: 0.60)
        descriptor.bluePrimary = CGPoint(x: 0.15, y: 0.06)
        descriptor.whitePoint = CGPoint(x: 0.3127, y: 0.3290)
        descriptor.queue = DispatchQueue.main

        guard let newDisplay = CGVirtualDisplay(descriptor: descriptor) else {
            print("[VirtualDisplay] Échec de création (API privée indisponible ?)")
            return nil
        }

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // Propose les résolutions natives Retina et standard pour l'iPad Air
        settings.modes = [
            CGVirtualDisplayMode(width: 2048, height: 1536, refreshRate: 60),
            CGVirtualDisplayMode(width: 1600, height: 1200, refreshRate: 60),
            CGVirtualDisplayMode(width: 1440, height: 1080, refreshRate: 60),
            CGVirtualDisplayMode(width: 1024, height: 768, refreshRate: 60),
            CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60),
            CGVirtualDisplayMode(width: 1280, height: 720, refreshRate: 60)
        ]
        guard newDisplay.apply(settings) else {
            print("[VirtualDisplay] applySettings a échoué")
            return nil
        }

        display = newDisplay
        virtualDisplayID = newDisplay.displayID
        print("[VirtualDisplay] Écran créé — ID \(newDisplay.displayID), \(width)×\(height) @ \(ppi) ppi")
        return newDisplay.displayID
    }

    /// Détruit l'écran virtuel (libération de la référence).
    func destroyVirtualDisplay() {
        guard virtualDisplayID != nil else { return }
        display = nil
        virtualDisplayID = nil
        print("[VirtualDisplay] Écran virtuel détruit")
    }
}
