# Logos des webradios

Dossier : `Resources/RadioLogos/`
Format : **PNG, carré, 512 x 512 px** (256 x 256 minimum), fond opaque ou transparent.
Nom : `radio_` + nom de la station en minuscules, sans accents, chaque suite de caractères
spéciaux ou d'espaces devenant un seul `_`. Uniquement a-z, 0-9 et `_`.

| Station | Nom du fichier |
|---|---|
| France Inter | `radio_france_inter.png` |
| franceinfo | `radio_franceinfo.png` |
| France Culture | `radio_france_culture.png` |
| France Musique | `radio_france_musique.png` |
| FIP | `radio_fip.png` |
| Mouv' | `radio_mouv.png` |
| RTL | `radio_rtl.png` |
| RTL2 | `radio_rtl2.png` |
| NRJ | `radio_nrj.png` |
| Skyrock | `radio_skyrock.png` |
| RMC | `radio_rmc.png` |
| Radio Classique | `radio_radio_classique.png` |
| Radio Nova | `radio_radio_nova.png` |
| WNYC FM 93.9 | `radio_wnyc_fm_93_9.png` |
| WNYC AM 820 | `radio_wnyc_am_820.png` |
| BBC Radio 5 Live | `radio_bbc_radio_5_live.png` |
| talkSPORT | `radio_talksport.png` |

Pour une station que tu ajoutes toi-même (« Ajouter une station… ») : même règle avec le nom saisi,
par exemple « Ma Radio » -> `radio_ma_radio.png`.

Après avoir ajouté les images : refaire un build (GitHub Actions) puis réinstaller.
Sans image, la station garde la pochette par défaut.
