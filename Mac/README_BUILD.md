# DisplayPADMac — Guide de création du projet Xcode

> **v0.1 — Skeleton de l'application menu bar macOS**  
> Les fichiers Swift sont dans `Mac/DisplayPADMac/Sources/`.  
> Ce guide explique comment créer le projet Xcode et y intégrer ces sources.

---

## Pourquoi pas de `.xcodeproj` généré automatiquement ?

Le fichier `project.pbxproj` est un format propriétaire complexe avec des UUIDs uniques par machine.  
Le générer à la main est fragile et difficile à maintenir dans Git.  
La solution recommandée est de créer le projet une fois via Xcode et de committer le `.xcodeproj` obtenu.

> **Alternative** : Un `Package.swift` SPM sera envisagé pour v0.2 (meilleure portabilité, pas de dépendance à Xcode GUI).

---

## Étape 1 — Créer le projet Xcode

1. Ouvrir **Xcode 15+**
2. **File → New → Project…**
3. Sélectionner : **macOS → App**
4. Options :
   - **Product Name** : `DisplayPADMac`
   - **Team** : votre Apple ID (ou "None" pour développement local)
   - **Organization Identifier** : `com.displaypad`
   - **Bundle Identifier** : `com.displaypad.mac` *(sera mis à jour)*
   - **Interface** : **SwiftUI**
   - **Language** : **Swift**
   - **Storage** : None
   - Décocher **Include Tests** (pour l'instant)
5. Enregistrer dans : `Mac/` *(le dossier `DisplayPADMac.xcodeproj` sera créé là)*

---

## Étape 2 — Supprimer les fichiers générés par défaut

Xcode génère `ContentView.swift` et `DisplayPADMacApp.swift`.  
**Les supprimer** (Move to Trash) depuis le Project Navigator.

---

## Étape 3 — Ajouter les fichiers sources

1. Dans le **Project Navigator**, clic droit sur le groupe `DisplayPADMac`
2. **Add Files to "DisplayPADMac"…**
3. Naviguer vers `Mac/DisplayPADMac/Sources/`
4. Sélectionner **tous les fichiers `.swift`** :
   - `AppDelegate.swift`
   - `AppSettings.swift`
   - `ConnectionManager.swift`
   - `PopoverView.swift`
   - `SettingsView.swift`
   - `StreamingEngine.swift`
   - `VirtualDisplay.swift`
5. Options : ✅ **Copy items if needed** → **Non** (les fichiers sont déjà dans le repo)  
   ✅ **Add to targets** : `DisplayPADMac`
6. Cliquer **Add**

---

## Étape 4 — Patcher le fichier Info.plist

1. Dans **Build Settings** du target `DisplayPADMac`, chercher **Info.plist File**
2. Remplacer la valeur par : `Mac/DisplayPADMac/Info.plist`
3. Vérifier que **Generate Info.plist File** est désactivé (ou mettre le chemin custom)

---

## Étape 5 — Ajouter les frameworks requis

Dans **Build Phases → Link Binary With Libraries**, ajouter :

| Framework | Requis pour |
|-----------|-------------|
| `ScreenCaptureKit.framework` | Capture d'écran (macOS 12.3+) |
| `VideoToolbox.framework` | Encodage H.264 |
| `CoreMedia.framework` | Types CMSampleBuffer, CMTime |
| `CoreGraphics.framework` | CGVirtualDisplay, CGDirectDisplayID |
| `Network.framework` | NWConnection (TCP) |

---

## Étape 6 — Configurer les entitlements

1. Dans **Signing & Capabilities**, cliquer **+ Capability** et ajouter :
   - **Hardened Runtime** (requis pour la distribution)
   - **Screen Recording** (entitlement `com.apple.security.screen-capture`)

2. Dans le fichier `.entitlements` généré, ajouter si nécessaire :

```xml
<key>com.apple.security.screen-capture</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

---

## Étape 7 — Configurer le Deployment Target

Dans **Build Settings → macOS Deployment Target** : **12.3** minimum  
(ScreenCaptureKit est disponible depuis macOS 12.3)

---

## Étape 8 — Build & Run

```bash
# Depuis Xcode : Cmd+R
# Ou en ligne de commande :
xcodebuild -project Mac/DisplayPADMac.xcodeproj \
           -scheme DisplayPADMac \
           -configuration Debug \
           build
```

L'app apparaît dans la barre des menus avec l'icône `display` (SF Symbols).

---

## Test rapide sans iPad

1. Lancer `iproxy 7000:7000` dans un terminal (depuis `libimobiledevice`)
2. Brancher l'iPad (ou utiliser le simulateur de protocole prévu en v0.3)
3. Cliquer sur l'icône dans la barre des menus → **Connecter**
4. Vérifier les logs dans Xcode Console

---

## Prochaines étapes (roadmap)

| Version | Objectif |
|---------|----------|
| v0.1 ✅ | Skeleton Swift, protocole binaire, UI menu bar |
| v0.2 | Encodage H.264 réel + envoi frames |
| v0.3 | Écran virtuel CGVirtualDisplay |
| v0.4 | Protocole complet, stats live, batterie |
| v1.0 | Release publique, App Store (si possible) |

---

## Ressources

- [DeskPad](https://github.com/vorner/DeskPad) — référence pour CGVirtualDisplay
- [ScreenCaptureKit Doc Apple](https://developer.apple.com/documentation/screencapturekit)
- [VideoToolbox H.264](https://developer.apple.com/documentation/videotoolbox)
- [libimobiledevice](https://libimobiledevice.org) — iproxy pour le tunnel USB
