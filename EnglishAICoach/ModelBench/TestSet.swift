import Foundation

/// Jeu d'essai de ModelBench. Phrases inventées, aucune donnée personnelle.
struct TestCase: Identifiable {
    enum Kind: String {
        case correction = "Correction"
        case french = "Explication en français"
        case chat = "Conversation"
    }

    let id = UUID()
    let kind: Kind
    /// Phrase de l'apprenant, ou consigne pour les autres types.
    let input: String
    /// Correction attendue (seulement pour les corrections).
    let expected: String?

    /// « /no_think » demande à Qwen3 de répondre sans phase de réflexion.
    var prompt: String {
        switch kind {
        case .correction:
            return """
            You are an English teacher for a French-speaking beginner. Correct the learner's sentence. \
            Reply with exactly two lines. Line 1 starts with "Corrected:" followed by the corrected sentence \
            (unchanged if it is already correct). Line 2 starts with "Explication:" followed by one short sentence in French. /no_think

            Learner's sentence: \(input)
            """
        case .french:
            return input + " /no_think"
        case .chat:
            return input + " /no_think"
        }
    }

    static let all: [TestCase] = [
        TestCase(kind: .correction, input: "I goed to school yesterday.", expected: "I went to school yesterday."),
        TestCase(kind: .correction, input: "She don't like apples.", expected: "She doesn't like apples."),
        TestCase(kind: .correction, input: "He have two brothers.", expected: "He has two brothers."),
        TestCase(kind: .correction, input: "I am agree with you.", expected: "I agree with you."),
        TestCase(kind: .correction, input: "We was happy to see them.", expected: "We were happy to see them."),
        TestCase(kind: .correction, input: "There is three books on the table.", expected: "There are three books on the table."),
        TestCase(kind: .correction, input: "I can to swim very well.", expected: "I can swim very well."),
        TestCase(kind: .correction, input: "My sister is more tall than me.", expected: "My sister is taller than me."),
        TestCase(kind: .correction, input: "Yesterday I have seen a film.", expected: "Yesterday I saw a film."),
        TestCase(kind: .correction, input: "I like very much football.", expected: "I like football very much."),
        TestCase(kind: .correction, input: "She is working here since two years.", expected: "She has been working here for two years."),
        TestCase(kind: .correction, input: "They are playing in the garden.", expected: "They are playing in the garden."),
        TestCase(kind: .french, input: "Explique en français, simplement, pourquoi on dit « She doesn't like » et pas « She don't like ».", expected: nil),
        TestCase(kind: .french, input: "Explique en français, simplement, la différence entre « I work » et « I am working ».", expected: nil),
        TestCase(kind: .chat, input: "You are a friendly English teacher. Speak simply (level A2). Greet the student and ask one easy question about their day.", expected: nil),
        TestCase(kind: .chat, input: "You are a friendly English teacher (level A2). The student says: \"I am go to cinema yesterday.\" Correct gently in one sentence, then ask one easy question.", expected: nil),
    ]
}
