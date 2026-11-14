// AppSettings.swift
// DisplayPADMac
//
// Paramètres de l'application, persistés avec UserDefaults via @AppStorage.
// Toutes les préférences utilisateur sont centralisées ici.

import SwiftUI
import Combine

// MARK: - Enums de préréglages

/// Résolutions disponibles pour le flux vidéo
enum ResolutionPreset: String, CaseIterable, Identifiable {
    case auto   = "auto"
    case r1024  = "1024x768"
    case r1366  = "1366x1024"
    case r2048  = "2048x1536"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .r1024: return "1024×768"
        case .r1366: return "1366×1024"
        case .r2048: return "2048×1536"
        }
    }
}

/// Fréquences d'images disponibles
enum FPSPreset: String, CaseIterable, Identifiable {
    case auto  = "auto"
    case fps15 = "15"
    case fps30 = "30"
    case fps60 = "60"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .fps15: return "15 fps"
        case .fps30: return "30 fps"
        case .fps60: return "60 fps"
        }
    }
}

/// Qualité / bitrate du flux H.264
enum QualityPreset: String, CaseIterable, Identifiable {
    case auto   = "auto"
    case low    = "low"
    case medium = "medium"
    case high   = "high"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:   return "Auto"
        case .low:    return "Faible (1 Mbps)"
        case .medium: return "Moyen (4 Mbps)"
        case .high:   return "Élevé (10 Mbps)"
        }
    }
}

/// Orientation de l'affichage
enum OrientationPreset: String, CaseIterable, Identifiable {
    case landscape = "landscape"
    case portrait  = "portrait"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .landscape: return "Paysage"
        case .portrait:  return "Portrait"
        }
    }

    /// Valeur entière envoyée dans le protocole binaire (0 = paysage, 1 = portrait)
    var protocolValue: UInt32 {
        switch self {
        case .landscape: return 0
        case .portrait:  return 1
        }
    }
}

/// Profil H.264 pour l'encodage
enum H264Profile: String, CaseIterable, Identifiable {
    case baseline = "baseline"
    case main     = "main"
    case high     = "high"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .baseline: return "Baseline"
        case .main:     return "Main"
        case .high:     return "High"
        }
    }
}

/// Thème de l'interface
enum AppTheme: String, CaseIterable, Identifiable {
    case automatic = "automatic"
    case light     = "light"
    case dark      = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatique"
        case .light:     return "Clair"
        case .dark:      return "Sombre"
        }
    }
}

// MARK: - AppSettings

/// Gestionnaire des paramètres de l'application, persisté avec UserDefaults.
class AppSettings: ObservableObject {

    // MARK: Préréglages vidéo

    @AppStorage("selectedResolution") var selectedResolution: ResolutionPreset = .auto
    @AppStorage("selectedFPS")        var selectedFPS: FPSPreset               = .auto
    @AppStorage("selectedQuality")    var selectedQuality: QualityPreset       = .auto
    @AppStorage("orientation")        var orientation: OrientationPreset       = .landscape

    // MARK: Connexion

    @AppStorage("tcpPort")        var tcpPort: Int        = 7100
    @AppStorage("autoReconnect")  var autoReconnect: Bool = true

    // MARK: Encodage

    @AppStorage("h264Profile") var h264Profile: H264Profile = .baseline

    // MARK: Comportement application

    @AppStorage("launchAtLogin") var launchAtLogin: Bool  = false
    @AppStorage("appTheme")      var appTheme: AppTheme   = .automatic

    // MARK: Visibilité des éléments du popover

    @AppStorage("showResolution")   var showResolution: Bool  = true
    @AppStorage("showFPS")          var showFPS: Bool          = true
    @AppStorage("showQuality")      var showQuality: Bool      = true
    @AppStorage("showOrientation")  var showOrientation: Bool  = true
    @AppStorage("showStats")        var showStats: Bool        = true
    @AppStorage("showBattery")      var showBattery: Bool      = true

    // MARK: - Computed properties (résolution d'Auto)

    /// Largeur réelle en pixels (résout "auto" → 1024)
    var actualWidth: Int {
        switch selectedResolution {
        case .auto:  return 1024
        case .r1024: return 1024
        case .r1366: return 1366
        case .r2048: return 2048
        }
    }

    /// Hauteur réelle en pixels (résout "auto" → 768)
    var actualHeight: Int {
        switch selectedResolution {
        case .auto:  return 768
        case .r1024: return 768
        case .r1366: return 1024
        case .r2048: return 1536
        }
    }

    /// FPS réel (résout "auto" → 30)
    var actualFPS: Int {
        switch selectedFPS {
        case .auto:  return 30
        case .fps15: return 15
        case .fps30: return 30
        case .fps60: return 60
        }
    }

    /// Bitrate réel en bits/s (résout "auto" → 4 Mbps)
    var actualBitrate: Int {
        switch selectedQuality {
        case .auto:   return 4_000_000
        case .low:    return 1_000_000
        case .medium: return 4_000_000
        case .high:   return 10_000_000
        }
    }
}
