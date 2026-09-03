import AppKit

@MainActor
final class ArtworkStore {
    static let shared = ArtworkStore()

    var countryCode: String? {
        didSet {
            if oldValue != countryCode {
                cache.removeAll()
            }
        }
    }

    private var cache: [String: NSImage] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    func image(for appID: Int64, bundleID: String = "") async -> NSImage? {
        let key = Self.key(appID: appID, bundleID: bundleID)
        if let cached = cache[key] { return cached }
        if appID != 0, let cached = cache["id:\(appID)"] { return cached }
        if let task = inflight[key] { return await task.value }

        let task = Task<NSImage?, Never> { [appID, bundleID] in
            await self.fetch(appID: appID, bundleID: bundleID)
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image {
            cache[key] = image
            if appID != 0 { cache["id:\(appID)"] = image }
        }
        return image
    }

    func placeholder(named name: String, size: CGFloat = 56) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.controlAccentColor.setFill()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSBezierPath(roundedRect: rect, xRadius: size * 0.223, yRadius: size * 0.223).fill()
        let letter = String(name.prefix(1))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.36, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: letter, attributes: attrs)
        let textSize = text.size()
        text.draw(at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2))
        image.unlockFocus()
        return image
    }

    private static func key(appID: Int64, bundleID: String) -> String {
        appID != 0 ? "id:\(appID)" : "b:\(bundleID)"
    }

    private func fetch(appID: Int64, bundleID: String) async -> NSImage? {
        guard let country = countryCode?.lowercased(), !country.isEmpty else { return nil }
        var urls: [String] = []
        if appID != 0 {
            urls.append("https://itunes.apple.com/lookup?id=\(appID)&country=\(country)")
        }
        if !bundleID.isEmpty {
            let encoded = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bundleID
            urls.append("https://itunes.apple.com/lookup?bundleId=\(encoded)&country=\(country)")
        }
        for urlString in urls {
            if let image = await lookupImage(urlString) {
                return image
            }
        }
        return nil
    }

    private func lookupImage(_ urlString: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        guard let decoded = try? JSONDecoder().decode(Lookup.self, from: data),
              let item = decoded.results.first else { return nil }
        guard var art = item.artworkUrl512 ?? item.artworkUrl100 else { return nil }
        art = art.replacingOccurrences(of: "http://", with: "https://")
        art = art.replacingOccurrences(of: "100x100bb", with: "200x200bb")
        guard let artURL = URL(string: art),
              let (imageData, _) = try? await URLSession.shared.data(from: artURL) else { return nil }
        return NSImage(data: imageData)
    }

    private struct Lookup: Decodable {
        struct Item: Decodable {
            var artworkUrl100: String?
            var artworkUrl512: String?
        }
        var results: [Item]
    }
}
