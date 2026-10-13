import SwiftUI

struct RewardedDiscoveryView: View {
    @EnvironmentObject private var allowance: DiscoveryAllowance
    @EnvironmentObject private var rewardedAds: RewardedAdService
    @Environment(\.dismiss) private var dismiss

    var notice: String? = nil
    var onUnlocked: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(AppTheme.sage)
                    .frame(width: 104, height: 104)
                    .background(AppTheme.sageLt)
                    .clipShape(Circle())

                VStack(spacing: 10) {
                    Text("Unlock another discovery")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(AppTheme.onSurface)
                        .multilineTextAlignment(.center)

                    Text("Watch one short ad to unlock one more personalized search. You choose when to watch—there are no interrupting ads.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button {
                    Task {
                        await rewardedAds.showRewardedDiscovery { token in
                            allowance.grantReward(token: token)
                            Haptics.success()
                            onUnlocked()
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if rewardedAds.isBusy || rewardedAds.isLoadingAd {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(buttonTitle)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(rewardedAds.isBusy || rewardedAds.isLoadingAd ? AppTheme.subtle : AppTheme.sage)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(rewardedAds.isBusy || rewardedAds.isLoadingAd)
                .accessibilityIdentifier("rewarded-ad-button")
                .accessibilityHint("Plays a rewarded ad and unlocks one discovery")

                if let message = rewardedAds.message ?? notice {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                }

                Text("Your free discovery refreshes each day.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.subtle)

                Spacer()
            }
            .padding(.horizontal, 24)
            .background(AppTheme.surface.ignoresSafeArea())
            .navigationTitle("More discoveries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppTheme.muted)
                        .disabled(rewardedAds.isBusy)
                }
            }
        }
        .task {
            if !rewardedAds.isReady { await rewardedAds.configure() }
        }
    }

    private var buttonTitle: String {
        if rewardedAds.isBusy || rewardedAds.isLoadingAd { return "Preparing ad…" }
        return rewardedAds.isReady ? "Watch ad to continue" : "Try loading ad"
    }
}

#Preview {
    RewardedDiscoveryView()
        .environmentObject(DiscoveryAllowance.shared)
        .environmentObject(RewardedAdService.shared)
}
