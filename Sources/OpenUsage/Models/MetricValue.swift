import Foundation

/// One measured number on a metric row, carried raw so that formatting happens only at the display
/// edge (see `MetricFormatter`).
///
/// A single row can hold several values — a daily-spend row carries dollars *and* tokens, a Codex
/// credits row carries dollars *and* a credit count — and the widget renders them all.
struct MetricValue: Hashable, Sendable, Codable {
    /// The raw magnitude: provider-reported USD for `.dollars`, 0...100 for `.percent`, an absolute count otherwise.
    var number: Double
    /// How this number prints ($ / % / plain count). Distinct per value within a row.
    var kind: MetricKind
    /// Unit noun shown after the number ("tokens", "credits", "available"). `nil` renders the number
    /// bare — a dollar amount takes its trailing word from the widget (`unboundedValueWord`) instead.
    var label: String?
    init(number: Double, kind: MetricKind, label: String? = nil) {
        self.number = number
        self.kind = kind
        self.label = label
    }
}
