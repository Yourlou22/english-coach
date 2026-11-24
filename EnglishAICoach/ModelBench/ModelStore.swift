import Foundation
import UIKit

/// Télécharge, vérifie et installe un modèle publié dans une release du dépôt.
@MainActor
final class ModelStore: ObservableObject {
    @Published var status = "Modèle pas encore téléchargé."
    @Published var progress: Double = 0
    @Published var busy = false
    @Published private(set) var modelFolder: URL?
    @Published private(set) var manifest: ModelManifest?

    private let downloader = Downloader()
    private static let owner = "Yourlou22"
    private static let repository = "english-coach"

    static func releaseBase(slug: String) -> URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases/download/model-\(slug)/")!
    }

    func reset() {
        modelFolder = nil
        manifest = nil
        progress = 0
        status = "Modèle pas encore téléchargé."
    }

    private func modelsDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }

    func prepare(slug: String) async {
        busy = true
        progress = 0
        modelFolder = nil
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            busy = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
        do {
            let directory = try modelsDirectory()
            let base = Self.releaseBase(slug: slug)

            status = "Lecture du manifeste…"
            let (data, response) = try await URLSession.shared.data(from: base.appendingPathComponent("manifest.json"))
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else { throw BenchError.http(code) }
            let manifest = try JSONDecoder().decode(ModelManifest.self, from: data)
            self.manifest = manifest

            let target = directory.appendingPathComponent(slug, isDirectory: true)
            let marker = directory.appendingPathComponent("\(slug).sha256")
            if let known = try? String(contentsOf: marker, encoding: .utf8),
               known == manifest.archive.sha256,
               FileManager.default.fileExists(atPath: target.path) {
                modelFolder = target
                status = "Modèle déjà installé : \(manifest.model), contexte \(manifest.contextLength)."
                return
            }

            let archive = directory.appendingPathComponent("\(slug).tar")
            let sizeText = ByteCountFormatter.string(fromByteCount: manifest.archive.size, countStyle: .file)
            status = "Téléchargement de \(sizeText) : gardez l'app ouverte et l'écran allumé."
            try await downloader.download(from: base.appendingPathComponent(manifest.archive.name), to: archive) { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: archive.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard size == manifest.archive.size else {
                throw BenchError.size(expected: manifest.archive.size, got: size)
            }

            status = "Vérification de l'empreinte SHA-256…"
            let digest = try await Task.detached { try Hashing.sha256(of: archive) }.value
            guard digest == manifest.archive.sha256 else { throw BenchError.hash }

            status = "Installation du modèle…"
            let partial = directory.appendingPathComponent("\(slug).partial", isDirectory: true)
            try? FileManager.default.removeItem(at: partial)
            try? FileManager.default.removeItem(at: target)
            try await Task.detached { try TarExtractor.extract(archive: archive, to: partial) }.value
            try FileManager.default.moveItem(at: partial, to: target)
            try manifest.archive.sha256.write(to: marker, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: archive)

            modelFolder = target
            status = "Modèle prêt : \(manifest.model), contexte \(manifest.contextLength), compression \(manifest.compression)."
        } catch {
            status = "Échec : \(error.localizedDescription)"
        }
    }
}
