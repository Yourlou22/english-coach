import SwiftUI
import UIKit

/// Écran d'essai d'un modèle de langage embarqué : téléchargement unique, puis mesures.
struct ModelBenchView: View {
    @StateObject private var store = ModelStore()
    @StateObject private var runner = BenchRunner()
    @State private var slug = "qwen3-0.6b"
    @State private var copied = false
    private let slugs = ["qwen3-0.6b", "qwen3-1.7b"]

    var body: some View {
        List {
            Section("Modèle") {
                Picker("Modèle", selection: $slug) {
                    ForEach(slugs, id: \.self) { Text($0).tag($0) }
                }
                .disabled(store.busy || runner.running)
                Text(store.status).font(.footnote)
                if store.busy { ProgressView(value: store.progress) }
                Button("Télécharger ou vérifier le modèle") {
                    Task { await store.prepare(slug: slug) }
                }
                .disabled(store.busy || runner.running)
            }

            Section("Essais") {
                Button("Charger le modèle et lancer les essais") {
                    if let folder = store.modelFolder {
                        Task { await runner.run(modelFolder: folder, slug: slug) }
                    }
                }
                .disabled(store.modelFolder == nil || store.busy || runner.running)
                if runner.running { ProgressView() }
                if !runner.status.isEmpty { Text(runner.status).font(.footnote) }
            }

            if !runner.summary.isEmpty {
                Section("Résumé") {
                    Text(runner.summary).font(.system(.footnote, design: .monospaced))
                    Button(copied ? "Rapport copié" : "Copier le rapport complet") {
                        UIPasteboard.general.string = runner.report
                        copied = true
                    }
                }
            }

            if !runner.results.isEmpty {
                Section("Détail") {
                    ForEach(runner.results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("[\(result.kind)] \(result.input)").font(.footnote).bold()
                            if let expected = result.expected {
                                Text("Attendu : \(expected)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(result.output.isEmpty ? "(aucune réponse)" : result.output).font(.caption)
                            if let error = result.error {
                                Text("Erreur : \(error)").font(.caption).foregroundStyle(.red)
                            }
                            if let matched = result.matched {
                                Text(matched ? "Correction exacte" : "Différente de l'attendu")
                                    .font(.caption2).foregroundStyle(matched ? .green : .orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("ModelBench")
        .onChange(of: slug) { store.reset() }
    }
}
