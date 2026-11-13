# DisplayPAD — Guide de compilation Theos

Guide pour compiler et déployer l'application iPad DisplayPAD avec [Theos](https://theos.dev).

---

## 1. Installation de Theos

```bash
# macOS (Homebrew requis)
brew install ldid make

# Cloner Theos
git clone --recursive https://github.com/theos/theos.git /opt/theos
export THEOS=/opt/theos
```

Ajouter à votre `~/.zshrc` ou `~/.bash_profile` :

```bash
export THEOS=/opt/theos
export PATH="$THEOS/bin:$PATH"
```

Puis recharger :

```bash
source ~/.zshrc
```

---

## 2. Toolchain iOS (SDK)

Theos a besoin du SDK iOS. Télécharger depuis [github.com/theos/sdks](https://github.com/theos/sdks) :

```bash
# Exemple pour iOS 12
curl -LO https://github.com/theos/sdks/releases/latest/download/iPhoneOS12.4.sdk.tar.xz
mkdir -p $THEOS/sdks
tar -xf iPhoneOS12.4.sdk.tar.xz -C $THEOS/sdks/
```

> **Note** : Pour armv7 (iPad Air 1), l'iOS 12 SDK suffit.

---

## 3. Variables d'environnement

| Variable             | Rôle                                      | Exemple                |
|----------------------|-------------------------------------------|------------------------|
| `THEOS`              | Chemin vers l'installation Theos          | `/opt/theos`           |
| `THEOS_DEVICE_IP`    | IP du device (via WiFi ou USB + iproxy)   | `127.0.0.1`            |
| `THEOS_DEVICE_PORT`  | Port SSH du device                        | `2222`                 |

Pour un déploiement via USB (recommandé) :

```bash
# Lancer iproxy pour SSH sur USB (port 22 → 2222 en local)
iproxy 2222:22 &

export THEOS_DEVICE_IP=127.0.0.1
export THEOS_DEVICE_PORT=2222
```

---

## 4. Compilation

Depuis le dossier `iPad/` :

```bash
cd iPad/

# Compiler (génère le .deb dans packages/)
make package

# Ou en mode debug (verbeux)
make package DEBUG=1
```

Le fichier `.deb` sera créé dans `iPad/packages/` :
```
packages/com.displaypad.ipad_0.1.0_iphoneos-arm.deb
```

---

## 5. Déploiement sur le device

### Via `make install` (SSH, recommandé)

```bash
# Avec iproxy actif et variables d'env configurées :
make install
```

Theos copie le `.deb` sur le device via SCP, l'installe avec `dpkg`, et redémarre SpringBoard.

### Via Sileo (manuel)

1. Copier le `.deb` sur l'iPad : `scp -P 2222 packages/*.deb root@127.0.0.1:/var/mobile/`
2. Sur l'iPad (SSH) : `dpkg -i /var/mobile/com.displaypad.ipad_*.deb`
3. `uicache` ou redémarrage SpringBoard : `killall SpringBoard`

---

## 6. Troubleshooting iOS 12 / armv7

### Erreur : `armv7 not supported`

Vérifier que le SDK iOS supporte armv7 :
```bash
ls $THEOS/sdks/iPhoneOS12.4.sdk/usr/lib/
```
Si absent, utiliser un SDK <= 12.x (iOS 13+ a supprimé armv7).

### Erreur : `ldid: command not found`

```bash
brew install ldid
# ou depuis Theos :
$THEOS/bin/ldid
```

### App ne s'ouvre pas sur l'iPad

- Vérifier les entitlements : `ldid -e DisplayPAD.app/DisplayPAD`
- Vérifier les frameworks linkés : `otool -L DisplayPAD.app/DisplayPAD`
- Consulter les logs : `idevicesyslog | grep DisplayPAD`

### Erreur de compilation ARC sur iOS 9

Les frameworks `CoreMedia` et `VideoToolbox` sont disponibles depuis iOS 8 — aucun problème attendu.
Si une erreur d'ARC apparaît, vérifier que `DisplayPAD_CFLAGS = -fobjc-arc` est bien dans le Makefile.

### Port 7000 déjà utilisé

Sur l'iPad, vérifier :
```bash
# En SSH sur le device
netstat -an | grep 7000
```
Tuer le processus occupant le port si nécessaire.

### Logs en temps réel

```bash
# Depuis macOS avec libimobiledevice
idevicesyslog | grep -i displaypad
```

---

## 7. Débogage

```bash
# Installer idevicesyslog
brew install libimobiledevice

# Voir les logs en temps réel
idevicesyslog | grep -E "(DisplayPAD|TCPReceiver|DisplayVC)"
```

---

## 8. Nettoyage

```bash
# Supprimer les objets compilés
make clean

# Supprimer aussi les packages
rm -rf packages/
```
