import AuthenticationServices
import SwiftUI

struct PurchaseView: View {
    @StateObject private var viewModel: PurchaseViewModel
    @ObservedObject private var purchases: PurchaseStore
    @ObservedObject private var account: AccountViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDeletionWarning = false
    @State private var showsApprovalWarning = false
    private let onContinue: (() -> Void)?

    init(intent: PurchaseViewModel.Intent = .profile, purchases: PurchaseStore? = nil,
         account: AccountViewModel? = nil, onContinue: (() -> Void)? = nil) {
        let store = purchases ?? .shared
        let identity = account ?? .shared
        _viewModel = StateObject(wrappedValue: PurchaseViewModel(intent: intent, purchases: store, account: identity))
        self.purchases = store
        self.account = identity
        self.onContinue = onContinue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("More delicious possibilities")
                        .font(AppTheme.display)
                        .foregroundStyle(AppTheme.onSurface)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { Haptics.light(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(AppTheme.sageLt, in: Circle())
                    }
                    .foregroundStyle(AppTheme.primaryInk)
                    .accessibilityLabel("Close discoveries")
                }

                if let wallet = purchases.wallet { balanceCard(wallet) }
                else if purchases.isLoading || account.isBusy { ProgressView("Checking your discoveries…").frame(maxWidth: .infinity) }

                if purchases.configuration.commerceEnabled {
                    passCard
                    if purchases.isProAvailable || purchases.hasActivePro {
                        proCard
                    }
                }

                if let title = viewModel.statusTitle, let message = viewModel.statusMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline)
                        Text(message).font(.subheadline).foregroundStyle(AppTheme.muted)
                        if purchases.hasPendingApproval {
                            action("Check approval") { Task { await viewModel.restore() } }
                                .disabled(purchases.isLoading || account.isBusy)
                            action("Request was declined or cancelled") { showsApprovalWarning = true }
                                .disabled(purchases.isLoading || account.isBusy)
                        }
                        if purchases.hasPendingSync {
                            action("Retry sync") { Task { await viewModel.retry() } }
                                .disabled(purchases.isLoading || account.isBusy)
                        } else if purchases.state == .unavailable || purchases.wallet == nil {
                            action("Try again") { Task { await viewModel.retry() } }
                                .disabled(purchases.isLoading || account.isBusy)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.sageLt, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("purchase-status")
                }

                if viewModel.canContinue, let onContinue {
                    action("Continue discovering", prominent: true) {
                        dismiss()
                        onContinue()
                    }
                    .accessibilityIdentifier("purchase-continue")
                }

                accountCard

                if purchases.hasPurchasesForAnotherAccount {
                    Text("Some purchases or requests aren’t linked to this Bilu account. Sign in with the account used for them to check their status.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                        .accessibilityIdentifier("purchase-other-account")
                }

                if account.isSignedIn {
                    action("Restore Purchases") { Task { await viewModel.restore() } }
                        .disabled(purchases.isLoading || account.isBusy)
                        .accessibilityIdentifier("purchase-restore")
                    Text("Sign in with the same Bilu account to recover your remaining purchased discoveries. Restore checks your App Store purchases and your Bilu balance.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.surface.ignoresSafeArea())
        .foregroundStyle(AppTheme.onSurface)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .task { await viewModel.load() }
        .alert("Was the request declined or cancelled?", isPresented: $showsApprovalWarning) {
            Button("Check and clear reminder") { Haptics.light(); Task { await viewModel.acknowledgeApproval() } }
            Button("Keep waiting", role: .cancel) {}
        } message: {
            Text("Confirm the request’s status with your parent or the App Store first. Clearing this reminder does not cancel Apple’s request. If it is still pending, buying again could result in two charges when approved.")
        }
        .confirmationDialog("Delete your Bilu account?", isPresented: $showsDeletionWarning, titleVisibility: .visible) {
            Button("Continue to account deletion", role: .destructive) {
                Haptics.error()
                account.isConfirmingDeletion = true
            }
            Button("Keep account", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and remaining discoveries. Pending purchases cannot move to a new account. Saved places on this device stay. Apple will confirm your identity before deletion.")
        }
    }

    private func balanceCard(_ wallet: PurchaseWallet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR DISCOVERIES").font(.caption.weight(.medium)).tracking(1)
                .foregroundStyle(AppTheme.muted)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 32) {
                    balance("Explore", count: wallet.remainingExplore)
                    balance("TikTok", count: wallet.remainingTikTok)
                }
                VStack(alignment: .leading, spacing: 16) {
                    balance("Explore", count: wallet.remainingExplore)
                    balance("TikTok", count: wallet.remainingTikTok)
                }
            }
            Text(wallet.plan == "pro"
                 ? "Bilu Pro: \(wallet.included.explore) Explore · \(wallet.included.tiktok) TikTok included"
                 : "Included: \(wallet.included.explore) Explore · \(wallet.included.tiktok) TikTok")
                .font(.subheadline)
            Text(wallet.plan == "pro"
                 ? "Your Pro discoveries refresh \(wallet.periodEnd.formatted(date: .abbreviated, time: .omitted))."
                 : "Included discoveries refresh \(wallet.periodEnd.formatted(date: .abbreviated, time: .omitted)).")
                .font(.footnote).foregroundStyle(AppTheme.muted)
            Text("Purchased: \(wallet.purchased.explore) Explore · \(wallet.purchased.tiktok) TikTok. No expiry.")
                .font(.footnote).foregroundStyle(AppTheme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("purchase-wallet")
    }

    private func balance(_ title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count.formatted()).font(AppTheme.display).foregroundStyle(AppTheme.primaryInk)
            Text(title).font(.headline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(title) discoveries remaining")
    }

    private var passCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Discovery Pass")
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(AppTheme.terracotta)
            }
            .font(AppTheme.title)
            Text("4 Explore discoveries + 1 TikTok discovery")
                .font(.headline)
            Text("A one-time purchase. Your purchased discoveries never expire. No subscription.")
                .font(.subheadline).foregroundStyle(AppTheme.muted)
            if let product = purchases.discoveryPass, purchases.isCommerceAvailable {
                action("Get Discovery Pass · \(product.displayPrice)", prominent: true) {
                    Task { await viewModel.purchaseDiscoveryPass() }
                }
                .disabled(!purchases.canPurchaseDiscoveryPass || account.isBusy || !account.isSignedIn)
                .accessibilityIdentifier("purchase-discovery-pass")
            } else if purchases.isLoading || account.isBusy {
                ProgressView("Loading Discovery Pass…").frame(minHeight: 44)
            } else {
                Text("Discovery Pass is currently unavailable.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
            }
            if !account.isSignedIn {
                Text("Sign in with Apple below to buy or restore your discoveries.")
                    .font(.footnote).foregroundStyle(AppTheme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
    }

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Bilu Pro").foregroundStyle(AppTheme.onSurface)
            } icon: {
                Image(systemName: "crown.fill").foregroundStyle(AppTheme.terracotta)
            }
            .font(AppTheme.title)
            Text("6 Explore discoveries + 1 TikTok discovery every service month")
                .font(.headline)

            if purchases.hasActivePro, let wallet = purchases.wallet {
                Text("Your current Pro allowance refreshes \(wallet.periodEnd.formatted(date: .abbreviated, time: .omitted)). Bilu Pro also keeps discovery loading ad-free.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                action("Manage subscription") {
                    guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
                    openURL(url)
                }
                .accessibilityIdentifier("purchase-manage-pro")
            } else {
                Text("More room for the occasions when you want a dependable answer, without promising unlimited provider work.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                if let product = purchases.proMonthly {
                    action("Start monthly · \(product.displayPrice) per month", prominent: true) {
                        Task { await viewModel.purchasePro(productID: product.id) }
                    }
                    .disabled(!purchases.canPurchasePro(product.id) || account.isBusy || !account.isSignedIn)
                    .accessibilityIdentifier("purchase-pro-monthly")
                }
                if let product = purchases.proAnnual {
                    action("Choose annual · \(product.displayPrice) per year") {
                        Task { await viewModel.purchasePro(productID: product.id) }
                    }
                    .disabled(!purchases.canPurchasePro(product.id) || account.isBusy || !account.isSignedIn)
                    .accessibilityIdentifier("purchase-pro-annual")
                }
                if purchases.proMonthly == nil && purchases.proAnnual == nil {
                    if purchases.isLoading || account.isBusy {
                        ProgressView("Loading Bilu Pro…").frame(minHeight: 44)
                    } else {
                        Text("Bilu Pro is currently unavailable.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                Text("Auto-renews until cancelled. Manage or cancel in the App Store.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.muted)
                if !account.isSignedIn {
                    Text("Sign in with Apple below to start or manage Bilu Pro.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(account.isSignedIn ? "Your Bilu account" : "Keep your discoveries with you")
                .font(.headline)
            if let message = account.message {
                Text(message).font(.subheadline).foregroundStyle(AppTheme.muted)
                    .accessibilityIdentifier("account-status")
            }
            if account.isBusy { ProgressView("Updating your account…") }
            if account.isConfirmingDeletion {
                Text("Confirm with Apple to permanently delete this Bilu account and its remaining discoveries.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                appleButton(purpose: .delete)
                    .disabled(!account.canChangeAccount)
                action("Keep account") { account.isConfirmingDeletion = false }
            } else if account.isSignedIn {
                Label("Signed in with Apple", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(AppTheme.primaryInk)
                Text("Your saved places stay on this device when you sign out or switch accounts.")
                    .font(.footnote).foregroundStyle(AppTheme.muted)
                if account.needsSignInRecovery {
                    Text("Reconnect with the Apple account you used for Bilu.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                    appleButton(purpose: .reconnect).disabled(!account.canChangeAccount)
                }
                action("Sign out") { Task { await account.signOut() } }
                    .disabled(!account.canChangeAccount)
                Button(role: .destructive) { Haptics.light(); showsDeletionWarning = true } label: {
                    Text("Delete account").font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(PurchasePressStyle(reduceMotion: reduceMotion))
                .disabled(!account.canChangeAccount)
                if purchases.hasPendingSync {
                    Text("A pending purchase stays with the Bilu account that bought it. Sign in with that account to finish syncing.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                }
                if !account.canChangeAccount && !account.isBusy {
                    Text("Wait for the current purchase operation to finish.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                }
            } else {
                Text("Continue browsing as a guest. Sign in when you’re ready to buy or restore a pass; your saved places stay right here.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                if account.useExistingAccount {
                    Text("Sign in to your existing Bilu account to recover purchases. Your local saved places will stay.")
                        .font(.footnote).foregroundStyle(AppTheme.muted)
                }
                appleButton(purpose: account.useExistingAccount ? .existingAccount : .signIn)
                    .disabled(account.isBusy || purchases.isLoading)
                action(account.useExistingAccount ? "Continue with this guest account" : "Use an existing Bilu account") {
                    account.useExistingAccount.toggle()
                }
                .disabled(account.isBusy || purchases.isLoading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func appleButton(purpose: AccountViewModel.ApplePurpose) -> some View {
        SignInWithAppleButton(.continue) { request in
            Haptics.light()
            account.prepareAppleRequest(request, purpose: purpose)
        } onCompletion: { result in
            Task { await account.completeAppleRequest(result) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(Capsule())
        .accessibilityIdentifier(purpose == .delete ? "account-confirm-delete" : "account-apple-signin")
    }

    private func action(_ title: String, prominent: Bool = false, perform: @escaping () -> Void) -> some View {
        Button {
            if prominent { Haptics.medium() } else { Haptics.light() }
            perform()
        } label: {
            Text(title).font(.body.weight(.semibold))
                .foregroundStyle(prominent ? AppTheme.white : AppTheme.primaryInk)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(prominent ? AppTheme.sage : AppTheme.sageLt, in: Capsule())
                .multilineTextAlignment(.center)
        }
        .buttonStyle(PurchasePressStyle(reduceMotion: reduceMotion))
    }
}

private struct PurchasePressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
