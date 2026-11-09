import Foundation
import SwiftUI

/// The Veil kit colours. Each family member gets their own kitten.
enum KittenColor: String, Codable, CaseIterable, Identifiable {
    case green, blue, purple, pink, orange, yellow, cyan, brown

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .green: Color(hex: 0x12C2A8)
        case .blue: Color(hex: 0x2F80FF)
        case .purple: Color(hex: 0x8B5CF6)
        case .pink: Color(hex: 0xFF3D9A)
        case .orange: Color(hex: 0xFF6B1A)
        case .yellow: Color(hex: 0xFFB020)
        case .cyan: Color(hex: 0x0EA5C6)
        case .brown: Color(hex: 0x9A6236)
        }
    }
}

/// Someone in the protected person's family, as seen from the protected person's phone.
struct FamilyMember: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var color: KittenColor
    /// How this person shows up in notifications: contact name variants and phone numbers.
    var contactNames: [String]
    var phoneNumbers: [String]
    var paired: Bool
    var addedAt = Date()
    /// Mum, Dad, Son… shown next to the name.
    var relationship: String?

    /// Does a notification title belong to this person?
    func matches(sender: String) -> Bool {
        let s = FamilyStore.normalise(sender)
        guard !s.isEmpty else { return false }
        if contactNames.map(FamilyStore.normalise).contains(where: { !$0.isEmpty && $0 == s }) { return true }
        let digits = sender.filter(\.isNumber)
        if digits.count >= 7 {
            return phoneNumbers.contains { n in
                let d = n.filter(\.isNumber)
                return d.count >= 7 && (d.hasSuffix(String(digits.suffix(8))) || digits.hasSuffix(String(d.suffix(8))))
            }
        }
        return false
    }
}

/// A code this phone can show: "my code for Mum" (family-member side).
struct FamilyKey: Codable, Identifiable, Hashable {
    var id: UUID
    var protectedName: String
    var myName: String
    var color: KittenColor
    var pairedAt = Date()
}

/// Family members and keys, stored on this phone. Secrets live in the Keychain, not here.
@MainActor
final class FamilyStore: ObservableObject {
    static let shared = FamilyStore()

    @Published private(set) var members: [FamilyMember] = []
    @Published private(set) var keys: [FamilyKey] = []

    private let membersKey = "familyMembers"
    private let keysKey = "familyKeys"

    private init() {
        load()
        makeTwoWay()
    }

    /// Pairings made before family codes were two-way: give each side what the other already has.
    private func makeTwoWay() {
        var changed = false
        for m in members where m.paired && !keys.contains(where: { $0.id == m.id }) {
            keys.append(FamilyKey(id: m.id, protectedName: m.name, myName: "", color: m.color)); changed = true
        }
        for k in keys where !members.contains(where: { $0.id == k.id }) {
            members.append(FamilyMember(id: k.id, name: k.protectedName, color: k.color,
                                        contactNames: [k.protectedName], phoneNumbers: [], paired: true)); changed = true
        }
        if changed { save() }
    }

    // MARK: Protected side

    /// Creates a member and a fresh secret. Returns the QR payload to show.
    func addMember(name: String, color: KittenColor, contactNames: [String], phones: [String], protectedName: String,
                   invite: String? = nil) -> PairingPayload {
        let id = UUID()
        let secret = FamilyCode.newSecret()
        SecretVault.save(secret, id: id)
        var names = contactNames
        if !names.contains(where: { FamilyStore.normalise($0) == FamilyStore.normalise(name) }) { names.append(name) }
        members.append(FamilyMember(id: id, name: name, color: color, contactNames: names, phoneNumbers: phones, paired: false))
        save()
        return PairingPayload(v: 1, id: id, protectedName: protectedName, memberName: name, color: color.rawValue, secret: secret,
                              invite: invite)
    }

    func payload(for member: FamilyMember, protectedName: String, invite: String? = nil) -> PairingPayload? {
        guard let secret = SecretVault.load(id: member.id) else { return nil }
        return PairingPayload(v: 1, id: member.id, protectedName: protectedName, memberName: member.name, color: member.color.rawValue,
                              secret: secret, invite: invite)
    }

    /// Marks a member paired and gives this phone its own code for them (two-way family code).
    func markPaired(_ id: UUID) {
        update(id) { $0.paired = true }
        if let m = member(id: id), !keys.contains(where: { $0.id == id }) {
            keys.append(FamilyKey(id: id, protectedName: m.name, myName: "", color: m.color))
            save()
        }
    }

    /// The scanning side also adds the other person as a family member, sharing the same secret,
    /// so messages from them get the same family-code check.
    func addMemberFromPairing(_ p: PairingPayload) {
        guard !members.contains(where: { $0.id == p.id }) else { return }
        members.append(FamilyMember(id: p.id, name: p.protectedName, color: KittenColor(rawValue: p.color) ?? .green,
                                    contactNames: [p.protectedName], phoneNumbers: [], paired: true))
        save()
    }

    static let relationships = ["Mum", "Dad", "Son", "Daughter", "Wife", "Husband", "Sister", "Brother",
                                "Grandma", "Grandpa", "Aunt", "Uncle", "Friend"]

    func update(_ id: UUID, _ change: (inout FamilyMember) -> Void) {
        guard let i = members.firstIndex(where: { $0.id == id }) else { return }
        change(&members[i])
        save()
    }

    func remove(_ id: UUID) {
        SecretVault.delete(id: id)
        members.removeAll { $0.id == id }
        keys.removeAll { $0.id == id }
        save()
    }

    func member(matching sender: String) -> FamilyMember? { members.first { $0.matches(sender: sender) } }
    func member(id: UUID) -> FamilyMember? { members.first { $0.id == id } }

    func verify(code: String, memberID: UUID) -> Bool {
        guard let secret = SecretVault.load(id: memberID) else { return false }
        return FamilyCode.verify(code, secret: secret)
    }

    // MARK: Family-member side

    func addKey(from payload: PairingPayload, myName: String) {
        SecretVault.save(payload.secret, id: payload.id)
        keys.removeAll { $0.id == payload.id }
        keys.append(FamilyKey(id: payload.id, protectedName: payload.protectedName, myName: myName,
                              color: KittenColor(rawValue: payload.color) ?? .blue))
        save()
    }

    func currentCode(for key: FamilyKey) -> String? {
        SecretVault.load(id: key.id).map { FamilyCode.code(secret: $0) }
    }

    // MARK: Helpers

    var nextColor: KittenColor {
        let used = Set(members.map(\.color))
        return KittenColor.allCases.dropFirst().first { !used.contains($0) } ?? .blue
    }

    nonisolated static func normalise(_ name: String) -> String {
        TextCleaner.clean(name).lowercased()
            .unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).union(.whitespaces).contains($0) }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
    }

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: membersKey), let m = try? JSONDecoder().decode([FamilyMember].self, from: data) { members = m }
        if let data = d.data(forKey: keysKey), let k = try? JSONDecoder().decode([FamilyKey].self, from: data) { keys = k }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(members), forKey: membersKey)
        d.set(try? JSONEncoder().encode(keys), forKey: keysKey)
    }

    #if DEBUG
    func resetForDemo() {
        members.forEach { SecretVault.delete(id: $0.id) }
        keys.forEach { SecretVault.delete(id: $0.id) }
        members = []; keys = []; save()
    }
    #endif
}
