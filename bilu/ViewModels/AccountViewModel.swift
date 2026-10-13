import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

@MainActor
final class AccountViewModel: ObservableObject {
    static let shared = AccountViewModel()
    @Published private(set) var account: BiluAccount?
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published var isConfirmingDeletion = false
    @Published var useExistingAccount = false
    @Published private(set) var needsSignInRecovery = false
    private let service: any AccountServicing
    private let purchases: PurchaseStore
    private var nonce: String?
    private var applePurpose: ApplePurpose = .signIn

    enum ApplePurpose { case signIn, existingAccount, reconnect, delete }

    init(service: any AccountServicing = AccountService(), purchases: PurchaseStore? = nil) {
        self.service = service
        self.purchases = purchases ?? .shared
    }

    var isSignedIn: Bool { account?.isAnonymous == false }
    var canChangeAccount: Bool {
        !isBusy && !purchases.isLoading && purchases.state != .purchasing
    }

    func loadCachedAccount() async { account = await service.cachedAccount() }

    func load() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        account = await service.cachedAccount()
        do {
            account = try await service.account()
            needsSignInRecovery = false
        } catch {
            needsSignInRecovery = true
            message = "Your account couldn’t connect. Your saved places and sign-in are still on this device."
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest, purpose: ApplePurpose = .signIn) {
        message = nil
        applePurpose = purpose
        do {
            let rawNonce = try Self.makeNonce()
            nonce = rawNonce
            request.nonce = Self.sha256(rawNonce)
            request.requestedScopes = [.email]
            isBusy = true
        } catch {
            nonce = nil
            message = "Apple sign-in couldn’t start. Please try again."
        }
    }

    func completeAppleRequest(_ result: Result<ASAuthorization, Error>) async {
        defer { isBusy = false; nonce = nil }
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce else { throw SupabaseAuthError.invalidResponse }
            let deletingID = applePurpose == .delete ? account?.id : nil
            if applePurpose == .delete && deletingID == nil { throw SupabaseAuthError.missingSession }
            let requiredID = applePurpose == .reconnect ? account?.id : deletingID
            account = try await service.signIn(idToken: token, nonce: nonce, requireAccount: requiredID,
                                               linkGuest: applePurpose == .signIn)
            needsSignInRecovery = false
            if let deletingID {
                guard let codeData = credential.authorizationCode,
                      let code = String(data: codeData, encoding: .utf8), !code.isEmpty else {
                    throw SupabaseAuthError.invalidResponse
                }
                try await service.deleteAccount(deletingID, authorizationCode: code)
                account = nil
                isConfirmingDeletion = false
                message = "Account deleted. Your saved places remain on this device."
            } else {
                message = "Signed in with Apple. Your saved places are ready."
            }
            await purchases.accountDidChange()
            Haptics.success()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            message = nil
        } catch SupabaseAuthError.accountMismatch {
            message = "Use the Apple account linked to this Bilu account. Your existing account hasn’t changed."
            Haptics.error()
        } catch {
            message = applePurpose == .delete
                ? "Your account wasn’t deleted. Check your connection and try again."
                : "Apple sign-in couldn’t finish. Check your connection and try again."
            Haptics.error()
        }
    }

    func signOut() async {
        guard canChangeAccount else {
            message = "Please wait for the current purchase operation to finish."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.signOut()
            account = nil
            message = "Signed out. Your saved places remain on this device."
            await purchases.accountDidChange()
        } catch { message = "Sign-out couldn’t finish. Please try again." }
    }

    static func makeNonce() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SupabaseAuthError.keychain(status) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
