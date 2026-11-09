import Foundation
import Supabase

/// This phone's seat in a family circle on the server.
/// Protected phone: one membership (`pairingID == nil`). Guardian phone: one per person they look out for.
struct Membership: Codable, Hashable {
    let circleID: UUID
    let memberID: UUID
    var pairingID: UUID?
}

/// A shared case, as stored in Supabase. Never contains the message text.
struct CaseRow: Codable, Identifiable, Hashable {
    let id: UUID
    let circle_id: UUID
    let protected_member_id: UUID
    let kind: String
    let level: Int
    let category: String
    let app: String?
    let sender_label: String?
    let claimed_identity: String?
    let requested_action: String?
    let summary_for_guardian: String
    let recommended_verification: String?
    let status: String
    let handled_by: UUID?
    let resolution: String?
    let verify_target_member_id: UUID?
    let verify_answer: String?
    let created_at: Date
}

struct MemberRow: Codable, Identifiable, Hashable {
    let id: UUID
    let circle_id: UUID
    let role: String
    let display_name: String
}

private struct NewCase: Encodable {
    let circle_id: UUID
    let protected_member_id: UUID
    let kind: String
    let level: Int
    let category: String
    let app: String
    let sender_label: String
    let claimed_identity: String?
    let requested_action: String?
    let summary_for_guardian: String
    let recommended_verification: String?
    let verify_target_member_id: UUID?
    let requested_by_user: Bool
}

/// Circles, shared cases, push registration and Realtime. Contract: docs/BACKEND_TASKS.md §3–5.
/// Every call is best-effort: without a backend the app keeps working on the phone alone.
@MainActor
final class CircleService: ObservableObject {
    static let shared = CircleService()

    @Published private(set) var memberships: [Membership] = []
    @Published private(set) var cases: [CaseRow] = []
    @Published private(set) var members: [MemberRow] = []
    /// Set when a push is tapped on a guardian phone, so the case list can scroll/highlight it.
    @Published var focusCaseID: UUID?

    private var channels: [UUID: RealtimeChannelV2] = [:]
    private var pushToken: String?
    private let storageKey = "circleMemberships"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Membership].self, from: data) { memberships = saved }
    }

    var protectedMembership: Membership? { memberships.first { $0.pairingID == nil } }

    func membership(forPairing id: UUID) -> Membership? { memberships.first { $0.pairingID == id } }

    // MARK: Protected side

    /// Creates the circle the first time, then returns a fresh single-use invite code for the QR.
    /// nil when the backend isn't set up: pairing still works offline.
    func inviteForPairing(myName: String) async -> String? {
        guard let client = await signedIn() else { return nil }
        do {
            if let m = protectedMembership {
                return try await client.rpc("refresh_invite_code", params: ["p_circle": m.circleID.uuidString]).execute().value
            }
            struct Created: Decodable { let circle_id: UUID; let invite_code: String; let member_id: UUID }
            let rows: [Created] = try await client.rpc("create_circle", params: ["p_display_name": Self.seatName(myName)]).execute().value
            guard let c = rows.first else { return nil }
            add(Membership(circleID: c.circle_id, memberID: c.member_id, pairingID: nil))
            await syncConsent()
            await registerDevice()
            await refresh()
            return c.invite_code
        } catch {
            return nil
        }
    }

    /// Shares a warning with the family. `requested` = she tapped "Ask family" (always pushes).
    func share(_ event: MessageEvent, requested: Bool) async {
        guard let m = protectedMembership, event.caseID == nil, await signedIn() != nil else { return }
        if members.isEmpty { await fetchAll() }
        let a = event.assessment
        let isFamily = event.familyCheck != nil || a?.category == "family_impersonation"
        let target = isFamily ? event.familyMemberID.flatMap(serverMemberID(forLocal:)) : nil
        await insert(NewCase(
            circle_id: m.circleID, protected_member_id: m.memberID,
            kind: isFamily ? "verify_identity" : "warning",
            level: max(1, min(3, event.level.rawValue)),
            category: a?.category ?? (isFamily ? "family_impersonation" : "other"),
            app: String(event.appLabel.prefix(40)), sender_label: String(event.senderLabel.prefix(60)),
            claimed_identity: a?.claimedIdentity, requested_action: a?.requestedAction,
            summary_for_guardian: String((a?.summaryForGuardian ?? "A message with warning signs.").prefix(400)),
            recommended_verification: a?.recommendedVerification,
            verify_target_member_id: target, requested_by_user: requested), for: event.id)
    }

    /// Result of the on-phone family code check. A wrong code is the strongest sign of impersonation:
    /// it becomes a Level 3 case so every guardian gets the urgent push.
    func reportFamilyCode(eventID: UUID, ok: Bool) async {
        guard let m = protectedMembership, let event = EventStore.shared.event(id: eventID),
              let client = await signedIn() else { return }
        if ok {
            guard let caseID = event.caseID else { return }
            _ = try? await client.from("cases").update(["status": "resolved", "resolution": "Family code matched."])
                .eq("id", value: caseID.uuidString).execute()
            return
        }
        let name = event.familyMemberID.flatMap { FamilyStore.shared.member(id: $0)?.name } ?? "family"
        await insert(NewCase(
            circle_id: m.circleID, protected_member_id: m.memberID, kind: "warning", level: 3,
            category: "family_impersonation",
            app: String(event.appLabel.prefix(40)), sender_label: String(event.senderLabel.prefix(60)),
            claimed_identity: name, requested_action: event.assessment?.requestedAction,
            summary_for_guardian: "Someone claiming to be \(name) gave the wrong family code.",
            recommended_verification: "Call \(name) on the number you already have.",
            verify_target_member_id: nil, requested_by_user: false), for: eventID)
        EventStore.shared.update(eventID) { $0.familyStatus = .shared }
    }

    func syncConsent() async {
        guard let m = protectedMembership, let client = await signedIn() else { return }
        _ = try? await client.from("members").update(["auto_share": Settings.autoShareSerious])
            .eq("id", value: m.memberID.uuidString).execute()
    }

    /// The server member id of a family member added on this phone. Matched by name, because the
    /// guardian joins with the name the protected person gave them in the QR.
    // shortcut: name match; two guardians with the same name would collide. Pass the pairing id
    // through join_circle if that ever matters.
    func serverMemberID(forLocal id: UUID) -> UUID? {
        guard let name = FamilyStore.shared.member(id: id)?.name else { return nil }
        let wanted = FamilyStore.normalise(name)
        return members.first { $0.role == "guardian" && FamilyStore.normalise($0.display_name) == wanted }?.id
    }

    // MARK: Guardian side

    /// Joins the circle named in a scanned QR, using the name the protected person knows us by.
    @discardableResult
    func join(code: String, as name: String, pairingID: UUID) async -> Bool {
        guard let client = await signedIn() else { return false }
        struct Joined: Decodable { let circle_id: UUID; let member_id: UUID }
        do {
            let rows: [Joined] = try await client.rpc("join_circle", params: ["p_code": code, "p_display_name": Self.seatName(name)])
                .execute().value
            guard let j = rows.first else { return false } // zero rows = used, wrong or expired code
            add(Membership(circleID: j.circle_id, memberID: j.member_id, pairingID: pairingID))
            await registerDevice()
            await refresh()
            return true
        } catch {
            return false
        }
    }

    func setStatus(_ c: CaseRow, _ status: String) async {
        guard let client = await signedIn(), let me = memberships.first(where: { $0.circleID == c.circle_id })?.memberID else { return }
        _ = try? await client.from("cases").update(["status": status, "handled_by": me.uuidString])
            .eq("id", value: c.id.uuidString).execute()
        await fetchAll()
    }

    /// "Was this you?" A real answer from the real person, never inferred from the AI.
    func answer(_ c: CaseRow, itWasMe: Bool) async {
        guard let client = await signedIn(), let me = memberships.first(where: { $0.circleID == c.circle_id })?.memberID else { return }
        _ = try? await client.from("cases")
            .update(["verify_answer": itWasMe ? "yes" : "no", "status": "resolved", "handled_by": me.uuidString])
            .eq("id", value: c.id.uuidString).execute()
        await fetchAll()
    }

    func name(of memberID: UUID?) -> String? { memberID.flatMap { id in members.first { $0.id == id }?.display_name } }

    // MARK: Push

    func setPushToken(_ token: Data) {
        pushToken = token.map { String(format: "%02x", $0) }.joined()
        Task { await registerDevice() }
    }

    private func registerDevice() async {
        guard let pushToken, !memberships.isEmpty, let client = await signedIn() else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"   // TestFlight and App Store builds
        #endif
        for m in memberships {
            _ = try? await client.rpc("register_device", params: [
                "p_member_id": m.memberID.uuidString, "p_token": pushToken, "p_environment": environment,
            ]).execute()
        }
    }

    /// A push was tapped: fetch the case (RLS-checked) and open it.
    func openCase(_ id: UUID) {
        focusCaseID = id
        Task {
            await refresh()
            if let event = EventStore.shared.events.first(where: { $0.caseID == id }) { Router.shared.open(event.id) }
        }
    }

    // MARK: Sync

    /// Fetch everything and make sure Realtime is listening. Called on launch, foreground and push.
    func refresh() async {
        await fetchAll()
        await subscribe()
    }

    private func fetchAll() async {
        guard !memberships.isEmpty, let client = await signedIn() else { return }
        let ids = memberships.map(\.circleID.uuidString)
        if let rows: [CaseRow] = try? await client.from("cases").select().in("circle_id", values: ids)
            .order("created_at", ascending: false).limit(50).execute().value {
            cases = rows
        }
        if let rows: [MemberRow] = try? await client.from("members").select("id,circle_id,role,display_name")
            .in("circle_id", values: ids).execute().value {
            members = rows
        }
        applyToEvents()
        markPairedMembers()
    }

    // shortcut: no timed polling while Realtime is down; the app refetches on foreground, on push
    // and on (re)subscribe instead. Add a 60 s timer here if demos show missed updates.
    private func subscribe() async {
        guard let client else { return }
        for m in memberships where channels[m.circleID] == nil {
            let channel = client.channel("circle-\(m.circleID.uuidString)")
            let caseChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "cases",
                                                     filter: .eq("circle_id", value: m.circleID.uuidString))
            let memberChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "members",
                                                       filter: .eq("circle_id", value: m.circleID.uuidString))
            channels[m.circleID] = channel
            await channel.subscribe()
            Task { for await _ in caseChanges { await self.fetchAll() } }
            Task { for await _ in memberChanges { await self.fetchAll() } }
        }
    }

    /// Protected phone: show what the family did on the matching local message.
    private func applyToEvents() {
        guard protectedMembership != nil else { return }
        let store = EventStore.shared
        for c in cases {
            guard let old = store.events.first(where: { $0.caseID == c.id }) else { continue }
            var e = old
            let helper = name(of: c.handled_by) ?? "Your family"
            let target = name(of: c.verify_target_member_id ?? c.handled_by) ?? "Your family"
            switch c.verify_answer {
            case "no": // stays an open warning on purpose
                e.familyCheck = .failed
                e.level = .urgent
                e.familyNote = "\(target) says this message is not from them. Don't reply or send money."
            case "yes":
                e.familyCheck = .verified
                e.familyStatus = .resolved
                e.familyNote = "\(target) says this message is from them."
            default:
                switch c.status {
                case "checking":
                    e.familyStatus = .checking
                    e.familyNote = "\(helper) is checking this for you. Wait before you reply."
                case "resolved":
                    e.familyStatus = .resolved
                    e.familyNote = c.resolution ?? "\(helper) has looked into it."
                default: break
                }
            }
            if e != old { store.upsert(e) }
        }
    }

    /// Protected phone: a family member counts as paired once they've joined the circle.
    private func markPairedMembers() {
        guard protectedMembership != nil else { return }
        for m in FamilyStore.shared.members where !m.paired && serverMemberID(forLocal: m.id) != nil {
            FamilyStore.shared.markPaired(m.id)
        }
    }

    // MARK: Helpers

    private var client: SupabaseClient? { SupabaseService.client }

    private func signedIn() async -> SupabaseClient? {
        guard let client, await SupabaseService.accessToken() != nil else { return nil }
        return client
    }

    private func insert(_ row: NewCase, for eventID: UUID) async {
        guard let client else { return }
        struct Inserted: Decodable { let id: UUID }
        if let r: Inserted = try? await client.from("cases").insert(row, returning: .representation)
            .select("id").single().execute().value {
            EventStore.shared.update(eventID) { $0.caseID = r.id }
        }
    }

    private func add(_ m: Membership) {
        memberships.removeAll { $0.circleID == m.circleID }
        memberships.append(m)
        UserDefaults.standard.set(try? JSONEncoder().encode(memberships), forKey: storageKey)
    }

    /// The server allows 1–40 characters.
    private static func seatName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Family" : String(trimmed.prefix(40))
    }
}
