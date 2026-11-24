import CryptoKit
import Foundation

enum BenchError: LocalizedError {
    case http(Int)
    case size(expected: Int64, got: Int64)
    case hash
    case tar(String)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "Réponse HTTP \(code) (le modèle n'est peut-être pas encore publié)."
        case .size(let expected, let got):
            return "Taille inattendue : \(got) octets au lieu de \(expected)."
        case .hash:
            return "L'empreinte SHA-256 ne correspond pas : fichier refusé."
        case .tar(let message):
            return "Archive illisible : \(message)"
        }
    }
}

/// Description d'un modèle publié (fichier manifest.json de la release).
struct ModelManifest: Codable {
    struct Archive: Codable {
        let name: String
        let size: Int64
        let sha256: String
    }

    let model: String
    let slug: String
    let contextLength: Int
    let compression: String
    let license: String
    let toolsRevision: String
    let archive: Archive
}

enum Hashing {
    /// SHA-256 d'un fichier, lu par blocs de 1 Mo (le fichier n'est jamais chargé en entier).
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Téléchargement avec suivi de progression.
final class Downloader {
    private var observation: NSKeyValueObservation?

    func download(from url: URL, to destination: URL, onProgress: @escaping (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                guard let tempURL, status == 200 else {
                    continuation.resume(throwing: BenchError.http(status))
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let value = progress.fractionCompleted
                DispatchQueue.main.async { onProgress(value) }
            }
            task.resume()
        }
        observation = nil
    }
}

/// Extraction minimale d'une archive tar au format ustar, fichier par fichier (sans tout charger en mémoire).
enum TarExtractor {
    static func extract(archive: URL, to destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var longName: String?

        while true {
            guard let header = try handle.read(upToCount: 512), header.count == 512 else { break }
            if header.allSatisfy({ $0 == 0 }) { break }

            let base = header.startIndex
            let name = text(header, base, 0, 100)
            let prefix = text(header, base, 345, 155)
            let sizeText = text(header, base, 124, 12).trimmingCharacters(in: .whitespaces)
            let size = Int64(sizeText, radix: 8) ?? 0
            let type = header[base + 156]
            var path = prefix.isEmpty ? name : prefix + "/" + name
            if let long = longName {
                path = long
                longName = nil
            }
            let padding = (512 - Int(size % 512)) % 512

            switch type {
            case UInt8(ascii: "5"):
                try manager.createDirectory(at: try target(path, in: destination), withIntermediateDirectories: true)
            case 0, UInt8(ascii: "0"):
                let output = try target(path, in: destination)
                try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                manager.createFile(atPath: output.path, contents: nil)
                let writer = try FileHandle(forWritingTo: output)
                defer { try? writer.close() }
                var remaining = size
                while remaining > 0 {
                    let wanted = Int(min(remaining, 1 << 20))
                    guard let data = try handle.read(upToCount: wanted), !data.isEmpty else {
                        throw BenchError.tar("fin de fichier inattendue")
                    }
                    try writer.write(contentsOf: data)
                    remaining -= Int64(data.count)
                }
                try skip(padding, in: handle)
            case UInt8(ascii: "L"):
                let data = try handle.read(upToCount: Int(size)) ?? Data()
                longName = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
                try skip(padding, in: handle)
            default:
                // Liens, en-têtes étendus et autres types : ignorés.
                try skip(Int(size) + padding, in: handle)
            }
        }
    }

    private static func skip(_ count: Int, in handle: FileHandle) throws {
        guard count > 0 else { return }
        let position = try handle.offset()
        try handle.seek(toOffset: position + UInt64(count))
    }

    private static func text(_ data: Data, _ base: Int, _ offset: Int, _ length: Int) -> String {
        let slice = data[(base + offset)..<(base + offset + length)]
        return String(decoding: slice.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Refuse les chemins absolus et ceux qui remontent hors du dossier de destination.
    private static func target(_ path: String, in destination: URL) throws -> URL {
        let parts = path.split(separator: "/").map(String.init)
        guard !path.hasPrefix("/"), !parts.contains("..") else {
            throw BenchError.tar("chemin refusé : \(path)")
        }
        return parts.filter { $0 != "." }.reduce(destination) { $0.appendingPathComponent($1) }
    }
}
