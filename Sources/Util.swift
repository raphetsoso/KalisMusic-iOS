import Foundation
import UIKit
import ImageIO
import SwiftUI

// MARK: - Erreurs

struct KError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

// MARK: - Chaînes

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }
    /// Nom de fichier en minuscules (clé de rapprochement des sauvegardes).
    var fileNameLower: String { (self as NSString).lastPathComponent.lowercased() }
}

func formatTime(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s)
    return String(format: "%d:%02d", t / 60, t % 60)
}

func formatListening(_ ms: Int64) -> String {
    let minutes = Int(ms / 60000)
    if minutes < 1 { return "Moins d'une minute" }
    if minutes < 60 { return "\(minutes) min" }
    return String(format: "%d h %02d min", minutes / 60, minutes % 60)
}

// MARK: - Expressions régulières (équivalent des Pattern/Matcher de Java)

enum Rx {
    struct Match {
        let groups: [String?]
        /// Position de fin (en unités UTF-16) du match complet.
        let end: Int
        subscript(i: Int) -> String {
            if i < groups.count, let g = groups[i] { return g }
            return ""
        }
    }

    static let dotAll: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]

    static func all(_ pattern: String, in s: String,
                    options: NSRegularExpression.Options = Rx.dotAll) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = s as NSString
        let found = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        var out: [Match] = []
        for m in found {
            var g: [String?] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                g.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            out.append(Match(groups: g, end: m.range.location + m.range.length))
        }
        return out
    }

    static func first(_ pattern: String, in s: String,
                      options: NSRegularExpression.Options = Rx.dotAll) -> Match? {
        return all(pattern, in: s, options: options).first
    }

    static func replace(_ pattern: String, in s: String, with template: String,
                        options: NSRegularExpression.Options = Rx.dotAll) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length),
                                           withTemplate: template)
    }

    static func tail(_ s: String, from utf16Offset: Int) -> String {
        let ns = s as NSString
        if utf16Offset >= ns.length { return "" }
        return ns.substring(from: utf16Offset)
    }
}

// MARK: - Images

enum ImageUtil {
    static func thumbnail(data: Data, maxDim: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    static func thumbnail(fileURL: URL, maxDim: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Réduit à 1024 px max et encode en JPEG.
    static func jpeg(fromData data: Data, maxDim: CGFloat = 1024) -> Data? {
        guard let img = thumbnail(data: data, maxDim: maxDim) else { return nil }
        return img.jpegData(compressionQuality: 0.9)
    }
}

// MARK: - Chemins

enum Paths {
    static let documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let music: URL = documents.appendingPathComponent("Music", isDirectory: true)
    static let support: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    static let covers: URL = support.appendingPathComponent("covers", isDirectory: true)
    static let caches: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    static func prepare() {
        let fm = FileManager.default
        for u in [music, support, covers, caches] {
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        }
    }

    /// Les morceaux sont repérés par un chemin relatif à Documents (« Music/x.mp3 ») : il survit aux réinstallations.
    static func url(forSource source: String) -> URL {
        return documents.appendingPathComponent(source)
    }

    /// Les pochettes sont repérées par un chemin relatif à Application Support (« covers/x.jpg »).
    static func url(forCover rel: String) -> URL {
        return support.appendingPathComponent(rel)
    }

    static func deleteCover(_ rel: String?) {
        guard let rel = rel, !rel.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(forCover: rel))
    }
}

// MARK: - Persistance (UserDefaults + JSON)

enum Persist {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    static func save<T: Encodable>(_ value: T, key: String) {
        if let d = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
}

// MARK: - Notification discrète (équivalent du Toast Android)

final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    @Published var message: String?

    func show(_ text: String) {
        DispatchQueue.main.async {
            self.message = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                if self.message == text { self.message = nil }
            }
        }
    }
}

// MARK: - État global de l'interface

final class AppState: ObservableObject {
    @Published var tab: Int = 4
    @Published var showNowPlaying = false
    @Published var showProfile = false
}

// MARK: - Thème (vert « Musique iOS 7-9 »)

enum Theme {
    static let accent = Color(red: 0 / 255, green: 165 / 255, blue: 55 / 255)          // #00A537
    static let gray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)         // #8E8E93
    static let separator = Color(red: 198 / 255, green: 210 / 255, blue: 201 / 255)
    static let barBg = Color(red: 243 / 255, green: 250 / 255, blue: 245 / 255)
    static let miniBg = Color(red: 240 / 255, green: 248 / 255, blue: 242 / 255)
    static let artBg = Color(red: 227 / 255, green: 238 / 255, blue: 230 / 255)
    static let nowPlayingBg = Color(red: 221 / 255, green: 246 / 255, blue: 229 / 255)
}
