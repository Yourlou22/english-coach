import CoreAILanguageModels
import Foundation
import FoundationModels
import UIKit

struct CaseResult: Identifiable {
    let id = UUID()
    let kind: String
    let input: String
    let expected: String?
    let output: String
    let firstToken: Double?
    let total: Double
    let charsPerSecond: Double?
    let matched: Bool?
    let error: String?
}

/// Charge un modèle Core AI et mesure vitesse, mémoire et exactitude sur le jeu d'essai.
@MainActor
final class BenchRunner: ObservableObject {
    @Published var running = false
    @Published var status = ""
    @Published var results: [CaseResult] = []
    @Published var summary = ""
    @Published var report = ""

    private let sampler = MemorySampler()

    func run(modelFolder: URL, slug: String) async {
        running = true
        results = []
        summary = ""
        report = ""
        defer { running = false }

        let availableBefore = MemoryProbe.availableBytes()
        let footprintBefore = MemoryProbe.footprintBytes()
        sampler.start()

        status = "Chargement du modèle…"
        let loadStart = Date()
        let model: CoreAILanguageModel
        do {
            model = try await CoreAILanguageModel(resourcesAt: modelFolder)
        } catch {
            sampler.stop()
            status = "Échec du chargement : \(error)"
            summary = status
            report = makeReport(slug: slug, load: nil, availableBefore: availableBefore, footprintBefore: footprintBefore)
            return
        }
        let loadSeconds = Date().timeIntervalSince(loadStart)

        for (index, test) in TestCase.all.enumerated() {
            status = "Essai \(index + 1) sur \(TestCase.all.count)…"
            let result = await runOne(test, model: model)
            results.append(result)
        }
        sampler.stop()
        status = "Terminé."
        summary = makeSummary(load: loadSeconds, availableBefore: availableBefore, footprintBefore: footprintBefore)
        report = makeReport(slug: slug, load: loadSeconds, availableBefore: availableBefore, footprintBefore: footprintBefore)
    }

    private func runOne(_ test: TestCase, model: CoreAILanguageModel) async -> CaseResult {
        let start = Date()
        var first: Double?
        var text = ""
        do {
            let session = LanguageModelSession(model: model)
            let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 200)
            let stream = session.streamResponse(to: test.prompt, options: options)
            for try await snapshot in stream {
                if first == nil { first = Date().timeIntervalSince(start) }
                text = snapshot.content
            }
        } catch {
            return CaseResult(kind: test.kind.rawValue, input: test.input, expected: test.expected, output: text,
                              firstToken: first, total: Date().timeIntervalSince(start), charsPerSecond: nil,
                              matched: nil, error: "\(error)")
        }
        let total = Date().timeIntervalSince(start)
        let clean = Self.withoutThinking(text)
        var speed: Double?
        if let first, total > first, !clean.isEmpty { speed = Double(clean.count) / (total - first) }
        var matched: Bool?
        if let expected = test.expected {
            matched = Self.correctedLine(in: clean).map { Self.normalize($0) == Self.normalize(expected) } ?? false
        }
        return CaseResult(kind: test.kind.rawValue, input: test.input, expected: test.expected, output: clean,
                          firstToken: first, total: total, charsPerSecond: speed, matched: matched, error: nil)
    }

    // MARK: Analyse des réponses

    static func withoutThinking(_ text: String) -> String {
        var result = text
        while let open = result.range(of: "<think>") {
            if let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
                result.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                result.removeSubrange(open.lowerBound..<result.endIndex)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func correctedLine(in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("corrected:") {
                return String(trimmed.dropFirst("corrected:".count))
            }
        }
        return nil
    }

    static func normalize(_ text: String) -> String {
        var value = text.lowercased()
        for quote in ["\u{2019}", "\u{2018}", "`"] { value = value.replacingOccurrences(of: quote, with: "'") }
        value = value.replacingOccurrences(of: "\"", with: "")
        value = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while let last = value.last, ".!?".contains(last) { value.removeLast() }
        return value.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Résumé et rapport

    private func makeSummary(load: Double, availableBefore: Int64, footprintBefore: Int64) -> String {
        let corrections = results.filter { $0.matched != nil }
        let good = corrections.filter { $0.matched == true }.count
        let firsts = results.compactMap { $0.firstToken }
        let speeds = results.compactMap { $0.charsPerSecond }
        let failures = results.filter { $0.error != nil }.count
        func mean(_ values: [Double]) -> String {
            values.isEmpty ? "n/d" : String(format: "%.2f", values.reduce(0, +) / Double(values.count))
        }
        return """
        Chargement : \(String(format: "%.1f", load)) s
        Premier mot (moyenne) : \(mean(firsts)) s
        Vitesse (moyenne) : \(mean(speeds)) caractères/s (≈ \(mean(speeds.map { $0 / 4 })) jetons/s, estimation)
        Corrections exactes : \(good) sur \(corrections.count)
        Essais en erreur : \(failures) sur \(results.count)
        Mémoire disponible avant : \(MemoryProbe.text(availableBefore))
        Mémoire disponible, pire moment : \(MemoryProbe.text(sampler.minAvailable))
        Empreinte avant : \(MemoryProbe.text(footprintBefore))
        Empreinte, pic : \(MemoryProbe.text(sampler.maxFootprint))
        """
    }

    private func makeReport(slug: String, load: Double?, availableBefore: Int64, footprintBefore: Int64) -> String {
        var lines = [
            "RAPPORT MODELBENCH",
            "Appareil : \(DeviceProbe.modelIdentifier()), iOS \(UIDevice.current.systemVersion)",
            "Modèle : \(slug)",
            summary,
            "",
        ]
        for result in results {
            lines.append("[\(result.kind)] \(result.input)")
            if let expected = result.expected { lines.append("  attendu : \(expected)") }
            lines.append("  réponse : \(result.output.replacingOccurrences(of: "\n", with: " / "))")
            let first = result.firstToken.map { String(format: "%.2f s", $0) } ?? "n/d"
            let speed = result.charsPerSecond.map { String(format: "%.1f car/s", $0) } ?? "n/d"
            let verdict = result.matched.map { $0 ? "exact" : "différent" } ?? "à relire"
            lines.append("  premier mot : \(first) ; total : \(String(format: "%.2f", result.total)) s ; vitesse : \(speed) ; verdict : \(verdict)")
            if let error = result.error { lines.append("  ERREUR : \(error)") }
        }
        return lines.joined(separator: "\n")
    }
}
