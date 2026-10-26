import Foundation

/// A data source that can register widgets it knows how to feed.
struct Provider: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// The provider mark drawn beside the name: a `ProviderKind.rawValue`, which names its SVG.
    let icon: String
    let accountLabel: String?
    /// The provider's quick links (e.g. "Status Page"), listed last in the dashboard card's right-click menu.
    let links: [ProviderLink]

    init(id: String, displayName: String, icon: String, accountLabel: String? = nil, links: [ProviderLink] = []) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.accountLabel = accountLabel
        self.links = links
    }

    /// "Claude · AM1": the provider and the account's name, for a menu item or dialog that has one line to
    /// tell accounts of the same provider apart.
    var fullName: String {
        guard let accountLabel, !accountLabel.isEmpty else { return displayName }
        return "\(displayName) · \(accountLabel)"
    }
}

/// One external quick link in a provider card's menu: a label and a URL opened in the default browser.
struct ProviderLink: Hashable {
    let label: String
    let url: URL
}
