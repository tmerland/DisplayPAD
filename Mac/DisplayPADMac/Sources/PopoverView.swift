// PopoverView.swift
// DisplayPADMac
//
// Vue principale du popover DisplayPAD (largeur 300pt).
// Design style macOS Tahoe : matière vitrée, typographie SF, contrôles natifs.

import SwiftUI

struct PopoverView: View {

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var connectionManager: ConnectionManager

    /// Affiche ou non la feuille de préférences
    @State private var afficherPreferences = false

    var body: some View {
        VStack(spacing: 0) {
            // ─── En-tête ───────────────────────────────────────────
            entete
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            // ─── Corps : paramètres ─────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    sectionConnexion
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    Divider().padding(.horizontal, 16)

                    sectionParametres
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    if connectionManager.isConnected && settings.showStats {
                        Divider().padding(.horizontal, 16)
                        sectionStats
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
            }

            Divider()

            // ─── Pied de page ───────────────────────────────────────
            piedDePage
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
        .background(.regularMaterial)
        .sheet(isPresented: $afficherPreferences) {
            SettingsView()
                .environmentObject(settings)
        }
    }

    // MARK: - En-tête

    private var entete: some View {
        HStack(spacing: 10) {
            // Icône de l'app
            Image(systemName: "display")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("DisplayPAD")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("v0.1.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Indicateur de statut animé (vert = connecté, orange = recherche, rouge = déconnecté)
            IndicateurStatut(
                connecte: connectionManager.isConnected,
                enRecherche: connectionManager.isConnecting
            )
        }
    }

    // MARK: - Section connexion

    private var sectionConnexion: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Nom du device
            HStack {
                Image(systemName: connectionManager.isConnected ? "ipad" : (connectionManager.isConnecting ? "antenna.radiowaves.left.and.right" : "ipad.slash"))
                    .foregroundStyle(connectionManager.isConnected ? Color.green : (connectionManager.isConnecting ? Color.orange : Color.secondary))
                Text(connectionManager.isConnected
                     ? "\(connectionManager.deviceName.isEmpty ? "iPad" : connectionManager.deviceName) connecté"
                     : (connectionManager.isConnecting ? "Recherche de l'iPad en cours…" : "iPad : Déconnecté"))
                    .font(.subheadline)
                    .foregroundStyle(connectionManager.isConnected ? .primary : .secondary)
                Spacer()
            }

            // Bouton Connecter / Déconnecter
            Button {
                if connectionManager.isConnected || connectionManager.isConnecting {
                    connectionManager.disconnect()
                } else {
                    connectionManager.connect(port: settings.tcpPort)
                }
            } label: {
                Text(connectionManager.isConnected ? "Déconnecter" : (connectionManager.isConnecting ? "Arrêter la recherche" : "Connecter"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(connectionManager.isConnected ? .red : (connectionManager.isConnecting ? .orange : .accentColor))
        }
    }

    // MARK: - Section paramètres

    private var sectionParametres: some View {
        VStack(spacing: 10) {
            if settings.showResolution {
                LignePicker(
                    label: "Résolution",
                    icone: "rectangle.on.rectangle",
                    selection: $settings.selectedResolution,
                    items: ResolutionPreset.allCases
                ) { $0.label }
            }

            if settings.showFPS {
                LignePicker(
                    label: "FPS",
                    icone: "gauge.with.dots.needle.bottom.50percent",
                    selection: $settings.selectedFPS,
                    items: FPSPreset.allCases
                ) { $0.label }
            }

            if settings.showQuality {
                LignePicker(
                    label: "Qualité",
                    icone: "dial.medium",
                    selection: $settings.selectedQuality,
                    items: QualityPreset.allCases
                ) { $0.label }
            }

            if settings.showOrientation {
                LignePicker(
                    label: "Orientation",
                    icone: "rectangle.landscape.rotate",
                    selection: $settings.orientation,
                    items: OrientationPreset.allCases
                ) { $0.label }
            }
        }
    }

    // MARK: - Section statistiques (visible seulement si connecté)

    private var sectionStats: some View {
        HStack {
            LigneStatistique(label: "FPS", valeur: String(format: "%.0f", connectionManager.currentFPS))
            Spacer()
            LigneStatistique(
                label: "Bitrate",
                valeur: formaterBitrate(connectionManager.currentBitrate)
            )
            Spacer()
            LigneStatistique(
                label: "Latence",
                valeur: String(format: "%.0f ms", connectionManager.currentLatency)
            )
            if settings.showBattery && connectionManager.batteryLevel >= 0 {
                Spacer()
                LigneStatistique(label: "Batterie", valeur: "\(connectionManager.batteryLevel)%")
            }
        }
    }

    // MARK: - Pied de page

    private var piedDePage: some View {
        HStack {
            Button {
                afficherPreferences = true
            } label: {
                Label("Préférences", systemImage: "gearshape")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quitter")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Utilitaires

    private func formaterBitrate(_ bitsParSeconde: Double) -> String {
        if bitsParSeconde >= 1_000_000 {
            return String(format: "%.1f Mbps", bitsParSeconde / 1_000_000)
        } else if bitsParSeconde >= 1_000 {
            return String(format: "%.0f Kbps", bitsParSeconde / 1_000)
        }
        return "\(Int(bitsParSeconde)) bps"
    }
}

// MARK: - Composants réutilisables

/// Indicateur de statut animé (vert = connecté, orange = recherche, rouge = déconnecté)
struct IndicateurStatut: View {

    let connecte: Bool
    var enRecherche: Bool = false
    @State private var pulse = false

    var body: some View {
        let couleur: Color = connecte ? .green : (enRecherche ? .orange : .red)
        ZStack {
            Circle()
                .fill(couleur.opacity(0.25))
                .frame(width: 20, height: 20)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0 : 1)
                .animation(
                    (connecte || enRecherche)
                        ? .easeInOut(duration: 1.2).repeatForever(autoreverses: false)
                        : .default,
                    value: pulse
                )

            Circle()
                .fill(couleur)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            if connecte || enRecherche { pulse = true }
        }
        .onChange(of: connecte) { _, newValue in
            pulse = newValue || enRecherche
        }
        .onChange(of: enRecherche) { _, newValue in
            pulse = newValue || connecte
        }
    }
}

/// Ligne de picker compact (label + SF icon + menu)
struct LignePicker<T: Hashable & Identifiable>: View {

    let label: String
    let icone: String
    @Binding var selection: T
    let items: [T]
    let titre: (T) -> String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icone)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.subheadline)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(items) { item in
                    Text(titre(item)).tag(item)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
        }
    }
}

/// Affichage d'une statistique (label + valeur)
struct LigneStatistique: View {
    let label: String
    let valeur: String

    var body: some View {
        VStack(spacing: 2) {
            Text(valeur)
                .font(.system(.subheadline, design: .monospaced).bold())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

