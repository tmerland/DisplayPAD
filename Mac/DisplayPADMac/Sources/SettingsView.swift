// SettingsView.swift
// DisplayPADMac
//
// Fenêtre de préférences de l'application DisplayPAD.
// Design style macOS Form avec sections groupées.

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    /// Valeur texte du port TCP pour la saisie
    @State private var portTexte: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // ─── Barre de titre ────────────────────────────────────
            HStack {
                Text("Préférences DisplayPAD")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // ─── Formulaire ────────────────────────────────────────
            Form {
                // Section : Comportement application
                Section("Application") {
                    Toggle("Lancer au démarrage", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, nouvelleValeur in
                            configurerLancementAuDemarrage(activer: nouvelleValeur)
                        }

                    Picker("Thème", selection: $settings.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                }

                // Section : Connexion
                Section("Connexion") {
                    HStack {
                        Text("Port TCP")
                        Spacer()
                        TextField("7000", text: $portTexte)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                            .onSubmit {
                                validerPort()
                            }
                    }

                    Toggle("Reconnexion automatique", isOn: $settings.autoReconnect)
                }

                // Section : Encodage vidéo
                Section("Encodage vidéo") {
                    Picker("Profil H.264", selection: $settings.h264Profile) {
                        ForEach(H264Profile.allCases) { profil in
                            Text(profil.label).tag(profil)
                        }
                    }
                }

                // Section : Éléments du popover
                Section("Éléments affichés dans le menu") {
                    Toggle("Résolution", isOn: $settings.showResolution)
                    Toggle("FPS", isOn: $settings.showFPS)
                    Toggle("Qualité", isOn: $settings.showQuality)
                    Toggle("Orientation", isOn: $settings.showOrientation)
                    Toggle("Statistiques (FPS réel / Bitrate)", isOn: $settings.showStats)
                    Toggle("Niveau de batterie iPad", isOn: $settings.showBattery)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 380, height: 480)
        .background(.regularMaterial)
        .onAppear {
            portTexte = "\(settings.tcpPort)"
        }
    }

    // MARK: - Utilitaires

    /// Valide et enregistre le port TCP saisi
    private func validerPort() {
        guard let port = Int(portTexte), (1...65535).contains(port) else {
            // Réinitialise à la valeur précédente si invalide
            portTexte = "\(settings.tcpPort)"
            return
        }
        settings.tcpPort = port
    }

    /// Configure le lancement au démarrage via ServiceManagement
    /// (nécessite l'entitlement com.apple.security.application-groups sur macOS 13+)
    private func configurerLancementAuDemarrage(activer: Bool) {
        // TODO (v0.2) : utiliser SMAppService.mainApp.register() / unregister()
        // sur macOS 13+ pour gérer le lancement au démarrage sans helper.
        // Pour l'instant, on enregistre simplement la préférence.
        print("[Settings] Lancement au démarrage : \(activer ? "activé" : "désactivé") (non encore implémenté)")
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
