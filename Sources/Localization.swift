import Foundation

/// Langue de l'appli : automatique (celle de l'iPhone), français, anglais, allemand ou espagnol.
final class Lang: ObservableObject {
    static let shared = Lang()
    static let codes = ["auto", "fr", "en", "de", "es"]

    @Published var setting: String {
        didSet { UserDefaults.standard.set(setting, forKey: "app_language") }
    }

    private init() {
        setting = UserDefaults.standard.string(forKey: "app_language") ?? "auto"
    }

    /// Langue réellement utilisée : fr, en, de ou es.
    var code: String {
        if setting != "auto" { return setting }
        for l in Locale.preferredLanguages {
            let p = String(l.prefix(2))
            if p == "fr" || p == "en" || p == "de" || p == "es" { return p }
        }
        return "en"
    }

    func translate(_ key: String) -> String {
        let c = code
        if c == "fr" { return key }
        var i = -1
        if c == "en" { i = 0 } else if c == "de" { i = 1 } else if c == "es" { i = 2 }
        guard i >= 0, let row = Strings.table[key], i < row.count else { return key }
        return row[i]
    }
}

/// Traduit un texte écrit en français (le texte français sert de clé).
func L(_ key: String) -> String { Lang.shared.translate(key) }

/// Même chose pour un texte avec valeurs (%@, %ld).
func LF(_ key: String, _ args: CVarArg...) -> String {
    return String(format: L(key), arguments: args)
}

enum Strings {
    // français (clé) -> [anglais, allemand, espagnol]
    static let table: [String: [String]] = [
        "Ce fichier n'est pas une sauvegarde KalisMusic.": ["This file is not a KalisMusic backup.", "Diese Datei ist keine KalisMusic-Sicherung.", "Este archivo no es una copia de seguridad de KalisMusic."],
        "Morceau suivant": ["Next track", "Nächster Titel", "Siguiente canción"],
        "Ouvrir le lecteur": ["Open player", "Player öffnen", "Abrir el reproductor"],
        "Lire": ["Play", "Abspielen", "Reproducir"],
        "Lire ensuite": ["Play next", "Als Nächstes abspielen", "Reproducir a continuación"],
        "Ajouter à la file d'attente": ["Add to queue", "Zur Warteschlange hinzufügen", "Añadir a la cola"],
        "Ajouter à une playlist…": ["Add to a playlist…", "Zu einer Playlist hinzufügen …", "Añadir a una lista…"],
        "Retirer des favoris": ["Remove from favorites", "Aus Favoriten entfernen", "Quitar de favoritos"],
        "Ajouter aux favoris": ["Add to favorites", "Zu Favoriten hinzufügen", "Añadir a favoritos"],
        "Retirer de la playlist": ["Remove from playlist", "Aus Playlist entfernen", "Quitar de la lista"],
        "Modifier les infos…": ["Edit info…", "Infos bearbeiten …", "Editar información…"],
        "Supprimer de l'appareil": ["Delete from device", "Vom Gerät löschen", "Eliminar del dispositivo"],
        "Supprimer ce morceau importé de votre appareil ?": ["Delete this imported track from your device?", "Diesen importierten Titel von deinem Gerät löschen?", "¿Eliminar esta canción importada de tu dispositivo?"],
        "Supprimer": ["Delete", "Löschen", "Eliminar"],
        "Annuler": ["Cancel", "Abbrechen", "Cancelar"],
        "Nouvelle playlist…": ["New playlist…", "Neue Playlist …", "Nueva lista…"],
        "Ajouter à une playlist": ["Add to a playlist", "Zu einer Playlist hinzufügen", "Añadir a una lista"],
        "Nouvelle playlist": ["New playlist", "Neue Playlist", "Nueva lista"],
        "Nom de la playlist": ["Playlist name", "Name der Playlist", "Nombre de la lista"],
        "Créer": ["Create", "Erstellen", "Crear"],
        "Rechercher": ["Search", "Suchen", "Buscar"],
        "Retour": ["Back", "Zurück", "Atrás"],
        "Pour vous": ["For You", "Für dich", "Para ti"],
        "Ma musique": ["My Music", "Meine Musik", "Mi música"],
        "Import": ["Import", "Import", "Importar"],
        "Aléatoire": ["Shuffle", "Zufällig", "Aleatorio"],
        "Album": ["Album", "Album", "Álbum"],
        "Morceaux": ["Songs", "Titel", "Canciones"],
        "Favoris": ["Favorites", "Favoriten", "Favoritos"],
        "Aucun morceau": ["No songs", "Keine Titel", "Sin canciones"],
        "Aucun résultat": ["No results", "Keine Ergebnisse", "Sin resultados"],
        "Aucune musique": ["No music", "Keine Musik", "Sin música"],
        "Ajoutez des morceaux depuis l'onglet Import.": ["Add songs from the Import tab.", "Füge Titel über den Tab „Import“ hinzu.", "Añade canciones desde la pestaña Importar."],
        "Écoutez de la musique et vos préférés apparaîtront ici.": ["Listen to some music and your favorites will appear here.", "Höre Musik, und deine Favoriten erscheinen hier.", "Escucha música y tus favoritos aparecerán aquí."],
        "Les plus écoutés": ["Most Played", "Am meisten gehört", "Más escuchado"],
        "Sélection pour vous": ["Picks for You", "Auswahl für dich", "Selección para ti"],
        "Nouveautés": ["New Arrivals", "Neuheiten", "Novedades"],
        "Genres": ["Genres", "Genres", "Géneros"],
        "Artistes": ["Artists", "Künstler", "Artistas"],
        "Albums": ["Albums", "Alben", "Álbumes"],
        "Bibliothèque": ["Library", "Mediathek", "Biblioteca"],
        "Playlists": ["Playlists", "Playlists", "Listas"],
        "Ajoutez des morceaux depuis l'onglet Import, ou copiez des fichiers dans le dossier KalisMusic/Music de l'application Fichiers.": ["Add songs from the Import tab, or copy files into the KalisMusic/Music folder in the Files app.", "Füge Titel über den Tab „Import“ hinzu oder kopiere Dateien in den Ordner KalisMusic/Music in der Dateien-App.", "Añade canciones desde la pestaña Importar o copia archivos a la carpeta KalisMusic/Music de la app Archivos."],
        "Ajouter de la musique": ["Add music", "Musik hinzufügen", "Añadir música"],
        "Shuffle": ["Shuffle", "Zufallswiedergabe", "Aleatorio"],
        "AJOUTÉS RÉCEMMENT": ["RECENTLY ADDED", "ZULETZT HINZUGEFÜGT", "AÑADIDO RECIENTEMENTE"],
        "Supprimer la playlist": ["Delete playlist", "Playlist löschen", "Eliminar lista"],
        "Supprimer cette playlist ?": ["Delete this playlist?", "Diese Playlist löschen?", "¿Eliminar esta lista?"],
        "téléchargement impossible": ["download failed", "Download nicht möglich", "descarga imposible"],
        "lien de téléchargement introuvable sur la page": ["download link not found on the page", "Download-Link auf der Seite nicht gefunden", "enlace de descarga no encontrado en la página"],
        "réponse invalide": ["invalid response", "ungültige Antwort", "respuesta no válida"],
        "le site demande une validation": ["the site requires verification", "die Website verlangt eine Bestätigung", "el sitio solicita una validación"],
        "lien introuvable": ["link not found", "Link nicht gefunden", "enlace no encontrado"],
        "le site demande une validation (connexion ou licence)": ["the site requires verification (login or license)", "die Website verlangt eine Bestätigung (Anmeldung oder Lizenz)", "el sitio solicita una validación (inicio de sesión o licencia)"],
        "fichier reçu trop petit": ["received file is too small", "empfangene Datei ist zu klein", "el archivo recibido es demasiado pequeño"],
        "pochette introuvable": ["cover not found", "Cover nicht gefunden", "carátula no encontrada"],
        "pochette vide": ["empty cover", "leeres Cover", "carátula vacía"],
        "Aucune lecture": ["Nothing playing", "Keine Wiedergabe", "Nada en reproducción"],
        "Fermer": ["Close", "Schließen", "Cerrar"],
        "CONNEXION…": ["CONNECTING…", "VERBINDEN …", "CONECTANDO…"],
        "EN DIRECT": ["LIVE", "LIVE", "EN DIRECTO"],
        "À suivre": ["Up Next", "Als Nächstes", "A continuación"],
        "Titre": ["Title", "Titel", "Título"],
        "Artiste": ["Artist", "Künstler", "Artista"],
        "Genre": ["Genre", "Genre", "Género"],
        "Choisir une pochette…": ["Choose a cover…", "Cover auswählen …", "Elegir una carátula…"],
        "Retirer la pochette": ["Remove cover", "Cover entfernen", "Quitar carátula"],
        "Appliquer album, artiste, genre et pochette à tout l'album": ["Apply album, artist, genre and cover to the whole album", "Album, Künstler, Genre und Cover auf das ganze Album anwenden", "Aplicar álbum, artista, género y carátula a todo el álbum"],
        "Rétablir les infos d'origine": ["Restore original info", "Originalinfos wiederherstellen", "Restablecer la información original"],
        "Enregistré": ["Saved", "Gespeichert", "Guardado"],
        "Les infos sont enregistrées dans l'appli (les fichiers ne sont pas modifiés).": ["Info is saved in the app (files are not modified).", "Die Infos werden in der App gespeichert (die Dateien werden nicht verändert).", "La información se guarda en la app (los archivos no se modifican)."],
        "Modifier les infos": ["Edit Info", "Infos bearbeiten", "Editar información"],
        "Enregistrer": ["Save", "Sichern", "Guardar"],
        "Impossible d'utiliser cette image": ["This image can't be used", "Dieses Bild kann nicht verwendet werden", "No se puede usar esta imagen"],
        "flux introuvable": ["stream not found", "Stream nicht gefunden", "emisión no encontrada"],
        "Fichier introuvable": ["File not found", "Datei nicht gefunden", "Archivo no encontrado"],
        "lecture impossible": ["playback failed", "Wiedergabe nicht möglich", "reproducción imposible"],
        "flux interrompu": ["stream interrupted", "Stream unterbrochen", "emisión interrumpida"],
        "Station indisponible. Vérifiez votre connexion ou l'adresse du flux.": ["Station unavailable. Check your connection or the stream address.", "Sender nicht verfügbar. Prüfe deine Verbindung oder die Stream-Adresse.", "Emisora no disponible. Comprueba tu conexión o la dirección de la emisión."],
        "Lecture impossible : ": ["Playback failed: ", "Wiedergabe nicht möglich: ", "No se puede reproducir: "],
        "Votre compte est local.": ["Your account is local.", "Dein Konto ist lokal.", "Tu cuenta es local."],
        "Musiques du KalisStore": ["KalisStore Music", "KalisStore-Musik", "Música de KalisStore"],
        "Historique des achats": ["Purchase History", "Kaufverlauf", "Historial de compras"],
        "Statistiques": ["Statistics", "Statistiken", "Estadísticas"],
        "Sauvegarde et restauration": ["Backup and Restore", "Sichern und Wiederherstellen", "Copia y restauración"],
        "À propos": ["About", "Info", "Acerca de"],
        "Réactiver le KalisStore": ["Re-enable KalisStore", "KalisStore wieder aktivieren", "Reactivar KalisStore"],
        "Retirer le KalisStore de l'interface": ["Remove KalisStore from the interface", "KalisStore aus der Oberfläche entfernen", "Quitar KalisStore de la interfaz"],
        "L'onglet KalisStore est masqué. Vos musiques téléchargées restent sur l'appareil.": ["The KalisStore tab is hidden. Your downloaded music stays on the device.", "Der Tab „KalisStore“ ist ausgeblendet. Heruntergeladene Musik bleibt auf dem Gerät.", "La pestaña KalisStore está oculta. Tu música descargada se conserva en el dispositivo."],
        "Masque l'onglet KalisStore. Vous pouvez le réactiver ici à tout moment.": ["Hides the KalisStore tab. You can re-enable it here at any time.", "Blendet den Tab „KalisStore“ aus. Du kannst ihn hier jederzeit wieder aktivieren.", "Oculta la pestaña KalisStore. Puedes reactivarla aquí en cualquier momento."],
        "Compte local": ["Local Account", "Lokales Konto", "Cuenta local"],
        "Masquer l'onglet KalisStore ? Vous pourrez le réactiver depuis cette page.": ["Hide the KalisStore tab? You can re-enable it from this page.", "Tab „KalisStore“ ausblenden? Du kannst ihn auf dieser Seite wieder aktivieren.", "¿Ocultar la pestaña KalisStore? Podrás reactivarla desde esta página."],
        "Aucune musique du KalisStore sur cet appareil.": ["No KalisStore music on this device.", "Keine KalisStore-Musik auf diesem Gerät.", "No hay música de KalisStore en este dispositivo."],
        "Retirer": ["Remove", "Entfernen", "Quitar"],
        "Uniquement les musiques téléchargées depuis le KalisStore. Retirer un morceau le supprime de l'appareil ; vous pourrez le retélécharger depuis le store.": ["Only music downloaded from KalisStore. Removing a track deletes it from the device; you can download it again from the store.", "Nur aus dem KalisStore heruntergeladene Musik. Beim Entfernen wird der Titel vom Gerät gelöscht; du kannst ihn erneut aus dem Store laden.", "Solo la música descargada de KalisStore. Quitar una canción la elimina del dispositivo; podrás volver a descargarla desde la tienda."],
        "Retirer cette musique de l'appareil ?": ["Remove this music from the device?", "Diese Musik vom Gerät entfernen?", "¿Quitar esta música del dispositivo?"],
        "Aucun achat pour l'instant.": ["No purchases yet.", "Noch keine Käufe.", "Aún no hay compras."],
        "Installé": ["Installed", "Installiert", "Instalado"],
        "Retiré": ["Removed", "Entfernt", "Quitado"],
        "Tout ce que vous avez téléchargé depuis le KalisStore, même si retiré depuis.": ["Everything you downloaded from KalisStore, even if removed since.", "Alles, was du aus dem KalisStore geladen hast, auch wenn es inzwischen entfernt wurde.", "Todo lo que has descargado de KalisStore, aunque lo hayas quitado después."],
        "Temps d'écoute": ["Listening Time", "Hördauer", "Tiempo de escucha"],
        "Morceaux joués": ["Tracks Played", "Gespielte Titel", "Canciones reproducidas"],
        "Morceau le plus joué": ["Most Played Track", "Meistgespielter Titel", "Canción más reproducida"],
        "Genre préféré": ["Favorite Genre", "Lieblingsgenre", "Género favorito"],
        "Artiste préféré": ["Favorite Artist", "Lieblingskünstler", "Artista favorito"],
        "Comptées sur cet appareil pendant la lecture.": ["Counted on this device during playback.", "Auf diesem Gerät während der Wiedergabe gezählt.", "Contado en este dispositivo durante la reproducción."],
        "MORCEAUX LES PLUS JOUÉS": ["MOST PLAYED TRACKS", "MEISTGESPIELTE TITEL", "CANCIONES MÁS REPRODUCIDAS"],
        "GENRES LES PLUS ÉCOUTÉS": ["MOST LISTENED GENRES", "AM MEISTEN GEHÖRTE GENRES", "GÉNEROS MÁS ESCUCHADOS"],
        "Réinitialiser les statistiques": ["Reset statistics", "Statistiken zurücksetzen", "Restablecer estadísticas"],
        "Réinitialiser toutes les statistiques d'écoute ?": ["Reset all listening statistics?", "Alle Hörstatistiken zurücksetzen?", "¿Restablecer todas las estadísticas de escucha?"],
        "Non": ["No", "Nein", "No"],
        "Oui": ["Yes", "Ja", "Sí"],
        "oui": ["yes", "ja", "sí"],
        "non": ["no", "nein", "no"],
        "Enregistrez vos playlists, tags, statistiques et données du KalisStore dans un fichier, puis restaurez-le sur un autre téléphone (iPhone ou Android).": ["Save your playlists, tags, statistics and KalisStore data to a file, then restore it on another phone (iPhone or Android).", "Sichere deine Playlists, Tags, Statistiken und KalisStore-Daten in einer Datei und stelle sie auf einem anderen Telefon wieder her (iPhone oder Android).", "Guarda tus listas, etiquetas, estadísticas y datos de KalisStore en un archivo y restáuralo en otro teléfono (iPhone o Android)."],
        "Exporter vers un fichier…": ["Export to a file…", "In Datei exportieren …", "Exportar a un archivo…"],
        "Restaurer depuis un fichier…": ["Restore from a file…", "Aus Datei wiederherstellen …", "Restaurar desde un archivo…"],
        "Le fichier contient : playlists et favoris, tags et pochettes modifiés, statistiques, stations de radio ajoutées, historique et liste de souhaits du KalisStore. Les morceaux eux-mêmes n'y sont pas. Sur le nouveau téléphone, importez d'abord vos morceaux, puis restaurez : chaque morceau est retrouvé par son nom de fichier.": ["The file contains: playlists and favorites, edited tags and covers, statistics, added radio stations, KalisStore history and wishlist. The songs themselves are not included. On the new phone, import your songs first, then restore: each song is matched by its file name.", "Die Datei enthält: Playlists und Favoriten, bearbeitete Tags und Cover, Statistiken, hinzugefügte Radiosender, KalisStore-Verlauf und Wunschliste. Die Titel selbst sind nicht enthalten. Importiere auf dem neuen Telefon zuerst deine Titel und stelle dann wieder her: Jeder Titel wird über seinen Dateinamen gefunden.", "El archivo contiene: listas y favoritos, etiquetas y carátulas editadas, estadísticas, emisoras añadidas, historial y lista de deseos de KalisStore. Las canciones en sí no se incluyen. En el teléfono nuevo, importa primero tus canciones y luego restaura: cada canción se encuentra por su nombre de archivo."],
        "Sauvegarde": ["Backup", "Sicherung", "Copia de seguridad"],
        "Sauvegarde enregistrée": ["Backup saved", "Sicherung gespeichert", "Copia guardada"],
        "Sauvegarde impossible : ": ["Backup failed: ", "Sicherung fehlgeschlagen: ", "No se pudo guardar la copia: "],
        "Changer la cover…": ["Change cover…", "Cover ändern …", "Cambiar carátula…"],
        "Ajouter une station…": ["Add a station…", "Sender hinzufügen …", "Añadir una emisora…"],
        "Supprimer cette station ?": ["Delete this station?", "Diesen Sender löschen?", "¿Eliminar esta emisora?"],
        "Nom de la station": ["Station name", "Name des Senders", "Nombre de la emisora"],
        "Site web ou adresse du flux (ex. www.fip.fr)": ["Website or stream address (e.g. www.fip.fr)", "Website oder Stream-Adresse (z. B. www.fip.fr)", "Sitio web o dirección de la emisión (p. ej. www.fip.fr)"],
        "Station AM (sinon FM)": ["AM station (otherwise FM)", "AM-Sender (sonst FM)", "Emisora AM (si no, FM)"],
        "Choisir une cover…": ["Choose a cover…", "Cover auswählen …", "Elegir una carátula…"],
        "Retirer la cover": ["Remove cover", "Cover entfernen", "Quitar carátula"],
        "Ajouter une station": ["Add Station", "Sender hinzufügen", "Añadir emisora"],
        "Ajouter": ["Add", "Hinzufügen", "Añadir"],
        "Saisissez un nom et le site web ou l'adresse du flux": ["Enter a name and the website or stream address", "Gib einen Namen und die Website oder Stream-Adresse ein", "Introduce un nombre y el sitio web o la dirección de la emisión"],
        "Cette station existe déjà": ["This station already exists", "Dieser Sender existiert bereits", "Esta emisora ya existe"],
        "Import…": ["Importing…", "Importiere …", "Importando…"],
        "Importez vos propres morceaux dans KalisMusic. Les fichiers importés sont copiés dans le dossier Music de l'application et apparaissent aussitôt dans votre bibliothèque.": ["Import your own songs into KalisMusic. Imported files are copied to the app's Music folder and appear in your library right away.", "Importiere deine eigenen Titel in KalisMusic. Importierte Dateien werden in den Ordner „Music“ der App kopiert und erscheinen sofort in deiner Mediathek.", "Importa tus propias canciones en KalisMusic. Los archivos importados se copian en la carpeta Music de la app y aparecen enseguida en tu biblioteca."],
        "Importer des morceaux…": ["Import songs…", "Titel importieren …", "Importar canciones…"],
        "Importer un dossier…": ["Import a folder…", "Ordner importieren …", "Importar una carpeta…"],
        "Actualiser la bibliothèque": ["Refresh library", "Mediathek aktualisieren", "Actualizar la biblioteca"],
        "Analyse de votre musique…": ["Scanning your music…", "Musik wird analysiert …", "Analizando tu música…"],
        "Application Fichiers : ouvrez « Sur mon iPhone » > KalisMusic > Music, copiez-y vos morceaux (MP3, M4A, FLAC, WAV, AIFF), puis touchez Actualiser la bibliothèque.": ["Files app: open “On My iPhone” > KalisMusic > Music, copy your songs there (MP3, M4A, FLAC, WAV, AIFF), then tap Refresh library.", "Dateien-App: Öffne „Auf meinem iPhone“ > KalisMusic > Music, kopiere deine Titel dorthin (MP3, M4A, FLAC, WAV, AIFF) und tippe auf „Mediathek aktualisieren“.", "App Archivos: abre «En mi iPhone» > KalisMusic > Music, copia allí tus canciones (MP3, M4A, FLAC, WAV, AIFF) y toca Actualizar la biblioteca."],
        "Depuis Windows : avec l'application « Appareils Apple », ouvrez votre iPhone > Partage de fichiers > KalisMusic, et glissez vos fichiers dans le dossier Music.": ["From Windows: with the “Apple Devices” app, open your iPhone > File Sharing > KalisMusic, and drag your files into the Music folder.", "Von Windows aus: Öffne in der App „Apple Geräte“ dein iPhone > Dateifreigabe > KalisMusic und ziehe deine Dateien in den Ordner „Music“.", "Desde Windows: con la app «Dispositivos Apple», abre tu iPhone > Compartir archivos > KalisMusic y arrastra tus archivos a la carpeta Music."],
        "Téléchargements : tout morceau enregistré depuis Safari, Drive ou Dropbox peut être ajouté avec Importer des morceaux…": ["Downloads: any song saved from Safari, Drive or Dropbox can be added with Import songs…", "Downloads: Jeder aus Safari, Drive oder Dropbox gesicherte Titel kann über „Titel importieren …“ hinzugefügt werden.", "Descargas: cualquier canción guardada desde Safari, Drive o Dropbox puede añadirse con Importar canciones…"],
        "Jailbreak : avec Filza, copiez simplement les fichiers dans le dossier Documents/Music de l'application.": ["Jailbreak: with Filza, simply copy the files into the app's Documents/Music folder.", "Jailbreak: Kopiere die Dateien mit Filza einfach in den Ordner Documents/Music der App.", "Jailbreak: con Filza, copia simplemente los archivos en la carpeta Documents/Music de la app."],
        "Les formats OGG et WMA ne sont pas lisibles sur iOS.": ["OGG and WMA formats can't be played on iOS.", "Die Formate OGG und WMA können unter iOS nicht abgespielt werden.", "Los formatos OGG y WMA no se pueden reproducir en iOS."],
        "AUTRES FAÇONS D'AJOUTER DE LA MUSIQUE": ["OTHER WAYS TO ADD MUSIC", "WEITERE MÖGLICHKEITEN, MUSIK HINZUZUFÜGEN", "OTRAS FORMAS DE AÑADIR MÚSICA"],
        "Cette station diffuse par segments (HLS) et ne peut pas être enregistrée.": ["This station streams in segments (HLS) and can't be recorded.", "Dieser Sender sendet in Segmenten (HLS) und kann nicht aufgenommen werden.", "Esta emisora transmite por segmentos (HLS) y no se puede grabar."],
        "fichier temporaire impossible": ["temporary file error", "temporäre Datei nicht möglich", "archivo temporal imposible"],
        "Connexion interrompue.": ["Connection interrupted.", "Verbindung unterbrochen.", "Conexión interrumpida."],
        "Enregistrement trop court.": ["Recording too short.", "Aufnahme zu kurz.", "Grabación demasiado corta."],
        "Connexion interrompue : enregistrement partiel ajouté": ["Connection interrupted: partial recording added", "Verbindung unterbrochen: Teilaufnahme hinzugefügt", "Conexión interrumpida: grabación parcial añadida"],
        "Enregistrement ajouté à la bibliothèque": ["Recording added to the library", "Aufnahme zur Mediathek hinzugefügt", "Grabación añadida a la biblioteca"],
        "Enregistrement impossible : ": ["Recording failed: ", "Aufnahme nicht möglich: ", "No se pudo grabar: "],
        "Aucun morceau complet enregistré (restez plus longtemps sur la station)": ["No complete track recorded (stay longer on the station)", "Kein vollständiger Titel aufgenommen (bleib länger auf dem Sender)", "No se grabó ninguna canción completa (permanece más tiempo en la emisora)"],
        "Votre liste de souhaits est vide. Touchez l'étoile d'un morceau pour le garder pour plus tard.": ["Your wishlist is empty. Tap the star on a track to keep it for later.", "Deine Wunschliste ist leer. Tippe auf den Stern eines Titels, um ihn für später zu merken.", "Tu lista de deseos está vacía. Toca la estrella de una canción para guardarla para más tarde."],
        "Recherche…": ["Searching…", "Suche …", "Buscando…"],
        "Recherche impossible : ": ["Search failed: ", "Suche nicht möglich: ", "No se pudo buscar: "],
        "Ce morceau est déjà dans votre bibliothèque": ["This track is already in your library", "Dieser Titel ist bereits in deiner Mediathek", "Esta canción ya está en tu biblioteca"],
        "import impossible": ["import failed", "Import nicht möglich", "importación imposible"],
        "Ajouté à la bibliothèque": ["Added to the library", "Zur Mediathek hinzugefügt", "Añadido a la biblioteca"],
        "Écoute impossible : ": ["Preview failed: ", "Vorhören nicht möglich: ", "No se pudo escuchar: "],
        "erreur": ["error", "Fehler", "error"],
        "Tous": ["All", "Alle", "Todos"],
        "Tout afficher": ["Show all", "Alle anzeigen", "Mostrar todo"],
        "Liste de souhaits": ["Wishlist", "Wunschliste", "Lista de deseos"],
        "Musique libre d'utilisation de ncs.io. Créditez NCS si vous utilisez un morceau dans vos vidéos.": ["Royalty-free music from ncs.io. Credit NCS if you use a track in your videos.", "Lizenzfreie Musik von ncs.io. Nenne NCS als Quelle, wenn du einen Titel in deinen Videos verwendest.", "Música libre de derechos de ncs.io. Da crédito a NCS si usas una canción en tus vídeos."],
        "Ouvrir ncs.io": ["Open ncs.io", "ncs.io öffnen", "Abrir ncs.io"],
        "Royaume-Uni": ["United Kingdom", "Vereinigtes Königreich", "Reino Unido"],
        "France": ["France", "Frankreich", "Francia"],
        "adresse invalide": ["invalid address", "ungültige Adresse", "dirección no válida"],
        "liste de lecture trop imbriquée": ["playlist nested too deeply", "Wiedergabeliste zu tief verschachtelt", "lista de reproducción demasiado anidada"],
        "liste de lecture vide": ["empty playlist", "leere Wiedergabeliste", "lista de reproducción vacía"],
        "aucun flux audio trouvé sur la page": ["no audio stream found on the page", "kein Audiostream auf der Seite gefunden", "no se encontró ninguna emisión de audio en la página"],
        "aucun flux audio trouvé sur cette page web": ["no audio stream found on this web page", "kein Audiostream auf dieser Webseite gefunden", "no se encontró ninguna emisión de audio en esta página web"],
        "Moins d'une minute": ["Less than a minute", "Weniger als eine Minute", "Menos de un minuto"],
        "Langue": ["Language", "Sprache", "Idioma"],
        "Automatique": ["Automatic", "Automatisch", "Automático"],
        "Ajouté à « %@ »": ["Added to “%@”", "Zu „%@“ hinzugefügt", "Añadido a «%@»"],
        "%ld ajoutés, %ld ignorés": ["%ld added, %ld skipped", "%ld hinzugefügt, %ld übersprungen", "%ld añadidas, %ld omitidas"],
        "%ld morceaux": ["%ld songs", "%ld Titel", "%ld canciones"],
        "%ld albums • %ld morceaux": ["%ld albums • %ld songs", "%ld Alben • %ld Titel", "%ld álbumes • %ld canciones"],
        "%ld musiques KalisStore installées": ["%ld KalisStore songs installed", "%ld KalisStore-Titel installiert", "%ld canciones de KalisStore instaladas"],
        "%ld écoutes": ["%ld plays", "%ld Wiedergaben", "%ld reproducciones"],
        "%ld %% de votre temps d'écoute": ["%ld %% of your listening time", "%ld %% deiner Hörzeit", "%ld %% de tu tiempo de escucha"],
        "Restauré : %ld playlists, %ld morceaux modifiés, statistiques : %@, %ld entrées du KalisStore.": ["Restored: %ld playlists, %ld edited songs, statistics: %@, %ld KalisStore entries.", "Wiederhergestellt: %ld Playlists, %ld bearbeitete Titel, Statistiken: %@, %ld KalisStore-Einträge.", "Restaurado: %ld listas, %ld canciones editadas, estadísticas: %@, %ld entradas de KalisStore."],
        "%ld morceaux de la sauvegarde sont introuvables sur ce téléphone. Importez-les, puis restaurez à nouveau.": ["%ld songs from the backup were not found on this phone. Import them, then restore again.", "%ld Titel der Sicherung wurden auf diesem Telefon nicht gefunden. Importiere sie und stelle dann erneut wieder her.", "%ld canciones de la copia no se encuentran en este teléfono. Impórtalas y vuelve a restaurar."],
        "Toute ma musique • %ld morceaux": ["All my music • %ld songs", "Meine gesamte Musik • %ld Titel", "Toda mi música • %ld canciones"],
        "Import de %ld sur %ld… %@": ["Importing %ld of %ld… %@", "Import von %ld von %ld … %@", "Importando %ld de %ld… %@"],
        "Votre bibliothèque : %ld morceaux": ["Your library: %ld songs", "Deine Mediathek: %ld Titel", "Tu biblioteca: %ld canciones"],
        "%ld morceau ajouté à la bibliothèque": ["%ld track added to the library", "%ld Titel zur Mediathek hinzugefügt", "%ld canción añadida a la biblioteca"],
        "%ld morceaux ajoutés à la bibliothèque": ["%ld tracks added to the library", "%ld Titel zur Mediathek hinzugefügt", "%ld canciones añadidas a la biblioteca"],
        "Échec du téléchargement : %@\n\nVous pouvez aussi télécharger le morceau depuis le site NCS puis l'ajouter avec Importer des morceaux.": ["Download failed: %@

You can also download the track from the NCS website and add it with Import songs.", "Download fehlgeschlagen: %@

Du kannst den Titel auch von der NCS-Website laden und über „Titel importieren“ hinzufügen.", "Error en la descarga: %@

También puedes descargar la canción desde el sitio de NCS y añadirla con Importar canciones."],
        "Version %@\nUn lecteur musical inspiré de Musique sur iOS 7 à 9, adapté de KalisMusic for Android.": ["Version %@
A music player inspired by Music on iOS 7 to 9, adapted from KalisMusic for Android.", "Version %@
Ein Musik-Player im Stil der Musik-App von iOS 7 bis 9, angepasst von KalisMusic für Android.", "Versión %@
Un reproductor de música inspirado en Música de iOS 7 a 9, adaptado de KalisMusic para Android."],
        "Un seul morceau enregistré, incomplet : le titre n'a pas changé. Laissez tourner plus longtemps pour découper.": ["Only one track recorded, incomplete: the title never changed. Let it run longer to split tracks.", "Nur ein unvollständiger Titel aufgenommen: Der Titel hat sich nicht geändert. Lass die Aufnahme länger laufen, um Titel zu trennen.", "Solo se grabó una canción, incompleta: el título no cambió. Déjalo grabar más tiempo para separar canciones."],
        "Cette station n'envoie pas les titres : enregistrement en un seul fichier.": ["This station doesn't send track titles: recorded as a single file.", "Dieser Sender sendet keine Titel: als eine einzelne Datei aufgenommen.", "Esta emisora no envía los títulos: grabado en un solo archivo."],
    ]
}
