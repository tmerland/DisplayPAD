# DisplayPad : iPad Air 1 comme écran externe du Mac via USB

## 1. Contexte et objectif

Les solutions permettant d'utiliser un iPad comme second écran (Duet Display, Luna Display, etc.) sont payantes. L'objectif est de réaliser une alternative **gratuite et open source**, fonctionnant par **câble USB** (latence faible, sans Wi-Fi), en s'appuyant sur un **iPad Air 1 jailbreaké** (iOS 12.5.8) qui permet d'installer une application sans App Store ni signature développeur.

| Élément | Choix |
|---|---|
| Récepteur | iPad Air 1 (A7), iOS 12.5.8, jailbreaké |
| Émetteur | Mac sous macOS Tahoe 26.2 |
| Liaison | USB (Lightning) via `usbmuxd` |
| Distribution | Paquet `.deb` installable depuis Sileo (identifiant du type `com.<pseudo>.displaypad`) |
| Éditeur | VS Code |

## 2. Architecture

```
Mac (émetteur)                              iPad (récepteur)
 écran virtuel → capture → encodage H.264    décodage matériel → affichage plein écran
                          ↓  TCP via USB  ↑
                              usbmuxd
                          (touches → Mac)
```

## 3. Composants

### 3.1 Transport USB
- `usbmuxd`, déjà présent sur macOS, crée un tunnel TCP à travers le câble.
- L'application iPad écoute sur un port local (ex. `7000`) ; le Mac s'y connecte via le socket `/var/run/usbmuxd`.
- Pour les premiers tests : `iproxy 7000:7000` (paquet `libimobiledevice`, via Homebrew).

### 3.2 Application Mac (émetteur, Swift)
- **Écran virtuel** : `CGVirtualDisplay` (API privée) afin que macOS voie un vrai deuxième écran. Le projet open source DeskPad sert de référence ; sa compatibilité avec Tahoe 26.2 reste à vérifier.
- **Capture** : ScreenCaptureKit (`SCStream`), nécessite l'autorisation « Enregistrement de l'écran ».
- **Encodage** : VideoToolbox (`VTCompressionSession`), H.264 temps réel, sans B-frames, keyframe toutes les 1 à 2 s.
- **Interface** : application de barre des menus.

### 3.3 Application iPad (récepteur, Objective-C / Theos)
- Lecture du flux TCP et découpage en NAL units.
- Affichage via `AVSampleBufferDisplayLayer` (décodage matériel).
- Plein écran, veille désactivée (`idleTimerDisabled`), orientation verrouillée.
- Compilation avec **Theos** (template `iphone/application`), sortie en `.deb` via `make package`.

### 3.4 Tactile (optionnel)
- L'iPad renvoie les événements tactiles au Mac, injectés avec `CGEvent`.
- Nécessite l'autorisation Accessibilité côté Mac.

## 4. Plan de réalisation

1. **Preuve de concept** : VNC sur le Mac, client VNC sur l'iPad, tunnel `iproxy` pour mesurer la latence.
2. **Récepteur iPad minimal** : socket TCP + affichage d'un flux H.264.
3. **Validation du récepteur** : envoi d'un flux de test depuis le Mac avec `ffmpeg` sur `localhost:7000`.
4. **Émetteur Mac** : capture, encodage, envoi du flux.
5. **Écran virtuel** `CGVirtualDisplay`.
6. **Tactile** et finitions.
7. **Packaging** : génération du dépôt (`dpkg-scanpackages`, fichiers `Packages` / `Release`) et publication pour Sileo.

## 5. Risques et points de vigilance

- **API privée** `CGVirtualDisplay` : non documentée, susceptible de changer. Solution de repli : capturer un écran existant ou utiliser un émulateur HDMI.
- **Latence** : à surveiller (encodage temps réel, taille du tampon).
- **Jailbreak** : non permanent, à relancer après chaque redémarrage de l'iPad.
- **Matériel ancien** : batterie de plus de 10 ans, chaleur à gérer en usage prolongé.
- **Toolchain** : Xcode 26 ne cible plus bien iOS 12 ; l'app iPad se compile avec Theos.

## 6. Livrables attendus

- **DisplayPad (Mac)** : application de barre des menus émettrice.
- **DisplayPad (iPad)** : application réceptrice, empaquetée en `.deb`.
- Dépôt Sileo personnel hébergeant le paquet.
- Documentation d'installation et d'utilisation.
