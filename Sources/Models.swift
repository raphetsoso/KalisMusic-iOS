import Foundation

/// Un morceau de la bibliothèque, ou une station de webradio (stream == true).
struct Track: Identifiable, Hashable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var genre: String = ""
    /// Fichier : chemin relatif à Documents (« Music/x.mp3 »). Webradio : adresse du flux.
    var source: String = ""
    var duration: Double = 0
    var trackNo: Int = 0
    /// Date d'ajout, en secondes.
    var added: Double = 0
    var stream: Bool = false
    /// Nom de base du logo d'une webradio (RadioLogos/radio_<logo>.png).
    var logo: String = ""
    /// Cover choisie par l'utilisateur pour une webradio (chemin relatif à Application Support).
    var logoFile: String? = nil
    var albumKey: String = ""

    var id: String { source }

    static func == (a: Track, b: Track) -> Bool { a.source == b.source }
    func hash(into hasher: inout Hasher) { hasher.combine(source) }
}

struct Album: Identifiable {
    var key: String
    var name: String
    var artist: String
    var added: Double = 0
    var tracks: [Track] = []
    var id: String { key }
}
