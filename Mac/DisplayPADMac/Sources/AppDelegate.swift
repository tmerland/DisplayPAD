// AppDelegate.swift
// DisplayPADMac
//
// Point d'entrée de l'application menu bar DisplayPAD.
// L'app est configurée comme LSUIElement (pas d'icône dans le Dock).

import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Propriétés

    /// L'item dans la barre des menus
    private var statusItem: NSStatusItem!

    /// Le popover affiché au clic sur l'icône
    private var popover: NSPopover!

    /// Gestionnaire de connexion partagé
    private let connectionManager = ConnectionManager()

    /// Paramètres de l'application partagés
    private let appSettings = AppSettings()

    /// Moteur de capture + encodage H.264
    private let streamingEngine = StreamingEngine()

    /// Écran virtuel (API privée CGVirtualDisplay)
    private let virtualDisplay = VirtualDisplayManager()

    /// Moniteur d'événements globaux (pour fermer le popover au clic extérieur)
    private var eventMonitor: Any?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurerStatusItem()
        configurerPopover()
        configurerSession()
        // Déclenche la demande d'autorisation « Enregistrement de l'écran »
        if !CGPreflightScreenCaptureAccess() {
            print("[App] Autorisation d'enregistrement de l'écran absente — demande en cours")
            _ = CGRequestScreenCaptureAccess()
        }
        // Lance la connexion au démarrage si l'auto-reconnect est activé
        if appSettings.autoReconnect {
            connectionManager.connect(port: appSettings.tcpPort)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        streamingEngine.stopCapture()
        virtualDisplay.destroyVirtualDisplay()
        connectionManager.disconnect()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Session de streaming

    /// HELLO_ACK → CONFIG ; CONFIG_ACK → écran virtuel + capture ; déconnexion → arrêt.
    private func configurerSession() {
        streamingEngine.delegate = self

        // Synchroniser les statistiques réelles vers ConnectionManager (affichées dans le Popover)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.connectionManager.currentFPS = self.streamingEngine.measuredFPS
            self.connectionManager.currentBitrate = self.streamingEngine.measuredBitrate
        }

        connectionManager.onHelloAck = { [weak self] in
            guard let self else { return }
            self.connectionManager.sendConfig(settings: self.appSettings)
        }
        connectionManager.onConfigAck = { [weak self] in
            guard let self else { return }
            let w = UInt32(self.appSettings.actualWidth)
            let h = UInt32(self.appSettings.actualHeight)
            // Écran virtuel si disponible, sinon repli sur l'écran principal
            let id = self.virtualDisplay.createVirtualDisplay(width: w, height: h, ppi: 264)
                ?? CGMainDisplayID()
            self.streamingEngine.startCapture(displayID: id, settings: self.appSettings)
        }
        connectionManager.onDisconnected = { [weak self] in
            self?.streamingEngine.stopCapture()
            self?.virtualDisplay.destroyVirtualDisplay()
        }
    }

    // MARK: - Configuration de la barre des menus

    /// Configure l'icône SF Symbol dans la barre des menus
    private func configurerStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else { return }

        // Icône "display" disponible en SF Symbols macOS
        let image = NSImage(systemSymbolName: "display", accessibilityDescription: "DisplayPAD")
        image?.isTemplate = true // S'adapte au thème clair/sombre
        button.image = image
        button.toolTip = "DisplayPAD"
        button.action = #selector(togglePopover(_:))
        button.target = self
    }

    // MARK: - Configuration du popover

    private func configurerPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 500)
        popover.behavior = .transient
        popover.animates = true

        // Injecte les objets partagés dans l'environnement SwiftUI
        let contentView = PopoverView()
            .environmentObject(appSettings)
            .environmentObject(connectionManager)

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    // MARK: - Actions

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            fermerPopover()
        } else {
            ouvrirPopover(sender)
        }
    }

    private func ouvrirPopover(_ sender: NSStatusBarButton) {
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // Ferme le popover si l'utilisateur clique ailleurs
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.fermerPopover()
        }
    }

    private func fermerPopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}


// MARK: - StreamingEngineDelegate

extension AppDelegate: StreamingEngineDelegate {
    nonisolated func didEncodeFrame(data: Data) {
        Task { @MainActor in self.connectionManager.sendFrame(data) }
    }
}
