# KalisMusic pour iOS

Port SwiftUI de KalisMusic for Android (iOS 16+). Pas besoin de Mac : la compilation se fait sur GitHub (gratuit).

## Fonctions reprises
Pour vous · Ma musique (Shuffle, ajoutés récemment, genres / artistes / albums / morceaux, playlists, favoris) ·
Radio FM/AM (stations ajoutables, covers, enregistrement) · Import (fichiers, dossiers) · KalisStore (ncs.io : recherche, genres,
écoute 30 s, téléchargement, liste de souhaits) · En lecture (file d'attente, volume, écran verrouillé) · modification des infos ·
statistiques · sauvegarde / restauration (même format que sur Android) · masquer le KalisStore.

Non repris : widget, easter egg, écriture des tags dans le fichier MP3 (les infos sont gardées dans l'appli),
formats OGG/WMA (illisibles sur iOS).

## 1. Compiler depuis Windows
1. Créez un compte sur github.com, puis un dépôt (Private ou Public) nommé `KalisMusic-iOS`.
2. Installez « Git for Windows », ouvrez un terminal dans ce dossier et tapez :
   ```
   git init
   git add .
   git commit -m "KalisMusic iOS"
   git branch -M main
   git remote add origin https://github.com/VOTRE_PSEUDO/KalisMusic-iOS.git
   git push -u origin main
   ```
3. Sur GitHub, onglet **Actions** : le build démarre tout seul (≈ 5-10 min). Si besoin, « Run workflow ».
4. Quand il est vert, ouvrez l'exécution et téléchargez l'artefact **KalisMusic-iOS** (un .zip) :
   - `com.kalismusic.ios_1.1_iphoneos-arm64.deb` → jailbreak rootless. Le binaire contient **arm64 et arm64e** :
     le même .deb convient aux iPhone A11 (8, X) comme aux A12 et plus récents.
   - `KalisMusic-unsigned.ipa` (arm64 seul, pour pouvoir être re-signé) → Sideloadly / AltStore, ou AppSync si votre jailbreak le propose

Le script `scripts/package.sh` refuse de produire les paquets si la tranche arm64 ou arm64e manque dans le binaire.
Variables utiles : `REQUIRE_ARM64E=0` (accepter un binaire sans arm64e), `IPA_FAT=1` (garder arm64e dans le .ipa).

Dépôt privé : les minutes macOS comptent 10× dans le quota gratuit (≈ 200 min/mois, soit une vingtaine de builds). Public : illimité.
Si le build est rouge, téléchargez l'artefact **build-log** et envoyez-moi le texte de l'erreur.

## 2. Installer sur l'iPhone jailbreaké (rootless)
1. Copiez le `.deb` sur le téléphone (AirDrop impossible depuis Windows : utilisez WinSCP/SFTP vers /var/mobile/Documents,
   ou envoyez-le vous par Telegram/e-mail et ouvrez-le avec Filza).
2. Dans Filza : touchez le .deb → **Installer**. Ou, dans un terminal : `sudo dpkg -i fichier.deb`.
3. Si l'icône n'apparaît pas : `uicache -p /var/jb/Applications/KalisMusic.app` (ou « Respring »).

L'appli est installée dans `/var/jb/Applications/KalisMusic.app`.

## 3. Ajouter de la musique
- Dans l'appli : onglet **Import** > Importer des morceaux / un dossier.
- Ou copiez vos fichiers dans le dossier `Documents/Music` de l'appli (Filza, Fichiers, « Appareils Apple » sur Windows),
  puis ouvrez l'appli (elle se rafraîchit toute seule).

## Logos des webradios
Mettez des PNG carrés dans `Resources/RadioLogos/` nommés `radio_<station>.png` (mêmes noms que sur Android, voir LOGOS_RADIOS.md),
puis refaites un build.
