import Foundation

/// When the Mac's speakers play a call, the mic can hear it too and the same
/// words would show up as both "Others" and "Me". A "Me" segment is dropped
/// when an "Others" segment overlaps it (within 1.5 s) with nearly the same
/// words.
public struct EchoDeduper: Sendable {
    public var slackMs: Int64 = 1_500
    public var threshold: Double = 0.8

    public init() {}

    public func shouldDrop(me: SegmentDraft, others: [SegmentDraft]) -> Bool {
        let mine = Self.words(me.text)
        guard !mine.isEmpty else { return true }
        for o in others where o.startMs - slackMs <= me.endMs && me.startMs <= o.endMs + slackMs {
            if Self.similarity(mine, Self.words(o.text)) >= threshold { return true }
        }
        return false
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Share of my words also present in theirs (multiset overlap).
    static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var counts: [String: Int] = [:]
        for w in b { counts[w, default: 0] += 1 }
        var hits = 0
        for w in a where (counts[w] ?? 0) > 0 {
            hits += 1
            counts[w]! -= 1
        }
        return Double(hits) / Double(a.count)
    }
}
