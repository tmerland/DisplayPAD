// AppDelegate.swift
// DisplayPADMac
//
// Point d'entrée de l'application menu bar DisplayPAD.
// L'app est configurée comme LSUIElement (pas d'icône dans le Dock).

import AppKit
import SwiftUI

@main
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

    /// Moniteur d'événements globaux (pour fermer le popover au clic extérieur)
    private var eventMonitor: Any?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurerStatusItem()
        configurerPopover()
        // Lance la connexion au démarrage si l'auto-reconnect est activé
        if appSettings.autoReconnect {
            connectionManager.connect(port: appSettings.tcpPort)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        connectionManager.disconnect()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
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
