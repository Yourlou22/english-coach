import SwiftUI

/// Écran « Hello iPhone » : relevé de l'appareil et demande d'accès au micro.
struct ContentView: View {
    @State private var deviceLines = DeviceProbe.deviceLines()
    @State private var speechLines = DeviceProbe.speechLines()
    @State private var voiceLines = DeviceProbe.voiceLines()
    @State private var microphone = DeviceProbe.microphoneStatus()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("ModelBench : essayer un modèle d'IA") { ModelBenchView() }
                }
                Section("Appareil") {
                    ForEach(deviceLines) { LabeledContent($0.label, value: $0.value) }
                }
                Section("Micro") {
                    LabeledContent("Autorisation", value: microphone)
                    Button("Demander l'accès au micro") {
                        Task {
                            _ = await DeviceProbe.requestMicrophone()
                            microphone = DeviceProbe.microphoneStatus()
                        }
                    }
                }
                Section("Reconnaissance vocale") {
                    ForEach(speechLines) { LabeledContent($0.label, value: $0.value) }
                }
                Section("Synthèse vocale") {
                    ForEach(voiceLines) { LabeledContent($0.label, value: $0.value) }
                }
                Section {
                    Button("Relire la mémoire disponible") {
                        deviceLines = DeviceProbe.deviceLines()
                    }
                }
            }
            .navigationTitle("Hello iPhone")
        }
    }
}

#Preview {
    ContentView()
}
