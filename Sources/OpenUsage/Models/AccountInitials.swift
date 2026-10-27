import Foundation

/// The tag on a menu-bar mark when a provider shows several accounts: the first letter of the
/// account name's first word and of its last, uppercased, the way Chakra's avatar fallback reads a
/// name. "Attention Machine 1" reads A1, "Personal" P, "rob@sunstory.com" R. Two names can share a
/// tag; renaming an account is how to tell them apart.
enum AccountInitials {
    static func tag(for name: String) -> String {
        let initials = name.split(whereSeparator: \.isWhitespace).compactMap(\.first)
        guard let first = initials.first else { return "" }
        let letters = initials.count > 1 ? [first, initials[initials.count - 1]] : [first]
        return String(letters).uppercased()
    }
}
