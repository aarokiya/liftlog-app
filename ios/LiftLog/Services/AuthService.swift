import Foundation
import Observation
import Supabase

/// Email + password or magic-link auth. Sign in with Apple needs a paid developer account, so it isn't used.
@MainActor
@Observable
final class AuthService {
    let client: SupabaseClient?
    private(set) var userId: UUID?
    private(set) var email: String?

    init() {
        client = AppConfig.supabase.map {
            SupabaseClient(supabaseURL: $0.url, supabaseKey: $0.key, options: .init(auth: .init(emitLocalSessionAsInitialSession: true)))
        }
        Task { await refresh() }
    }

    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { userId != nil }

    func refresh() async {
        guard let client else { return }
        if let session = try? await client.auth.session {
            apply(session)
        } else {
            userId = nil
            email = nil
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { return }
        apply(try await client.auth.signIn(email: email, password: password))
    }

    /// Returns true when Supabase wants the address confirmed before the first sign-in.
    func signUp(email: String, password: String) async throws -> Bool {
        guard let client else { return false }
        let response = try await client.auth.signUp(email: email, password: password, redirectTo: AppConfig.authRedirect)
        if let session = response.session {
            apply(session)
            return false
        }
        return true
    }

    func sendMagicLink(to email: String) async throws {
        try await client?.auth.signInWithOTP(email: email, redirectTo: AppConfig.authRedirect)
    }

    func handle(url: URL) async {
        _ = try? await client?.auth.session(from: url)
        await refresh()
    }

    /// Deletes the account and everything synced under it (RPC `delete_account`), then signs out. Data on the phone stays.
    func deleteAccount() async throws {
        guard let client else { return }
        try await client.rpc("delete_account").execute()
        await signOut()
    }

    func signOut() async {
        try? await client?.auth.signOut()
        UserDefaults.standard.removeObject(forKey: Prefs.profilePulled)
        userId = nil
        email = nil
    }

    private func apply(_ session: Session) {
        userId = session.user.id
        email = session.user.email
    }
}
