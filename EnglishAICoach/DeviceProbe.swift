import AVFoundation
import Foundation
import os
import Speech
import UIKit

/// Une ligne de relevé : un libellé et sa valeur.
struct ProbeLine: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

/// Relevés en lecture seule sur l'appareil. Aucune donnée ne quitte l'iPhone.
enum DeviceProbe {
    /// Identifiant matériel, par exemple « iPhone14,7 » pour un iPhone 14.
    static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static func megabytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    static func deviceLines() -> [ProbeLine] {
        [
            ProbeLine(label: "Modèle", value: modelIdentifier()),
            ProbeLine(label: "iOS", value: UIDevice.current.systemVersion),
            ProbeLine(label: "Mémoire physique", value: megabytes(Int64(ProcessInfo.processInfo.physicalMemory))),
            // Mesure clé pour le choix du modèle de langage : ce que le système laisse à l'app.
            ProbeLine(label: "Mémoire encore disponible pour l'app", value: megabytes(Int64(os_proc_available_memory()))),
        ]
    }

    static func speechLines() -> [ProbeLine] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            return [ProbeLine(label: "Reconnaissance en-US", value: "non prise en charge")]
        }
        return [
            ProbeLine(label: "Reconnaissance en-US disponible", value: recognizer.isAvailable ? "oui" : "non"),
            ProbeLine(label: "Reconnaissance sur l'appareil", value: recognizer.supportsOnDeviceRecognition ? "oui" : "non"),
        ]
    }

    static func voiceLines() -> [ProbeLine] {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let better = english.filter { $0.quality == .enhanced || $0.quality == .premium }
        return [
            ProbeLine(label: "Voix anglaises installées", value: "\(english.count)"),
            ProbeLine(label: "dont améliorées ou premium", value: "\(better.count)"),
        ]
    }

    static func microphoneStatus() -> String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "accordée"
        case .denied: return "refusée"
        case .undetermined: return "pas encore demandée"
        @unknown default: return "inconnue"
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
