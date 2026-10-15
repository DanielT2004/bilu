//
//  IntentSheet.swift
//  bilu
//
//  The action button's sheet: pick an intent, refine it, "Find spots".
//  Every intent goes through `HomeViewModel.applyIntent`.
//

import SwiftUI

struct IntentSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    /// Observed so the allowance line updates when a discovery or reward lands.
    @EnvironmentObject private var discoveryAllowance: DiscoveryAllowance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var intent: FeedIntent?
    @State private var refinement: IntentRefinement?
    @State private var lateNight = false
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What are you after?")
                    .font(AppTheme.title)
                    .foregroundStyle(AppTheme.onSurface)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 28)

                LocationChip(viewModel: viewModel)
                    .padding(.top, 14)

                ChipFlow(spacing: 10) {
                    ForEach(FeedIntent.allCases) { option in
                        chip(option.title, systemImage: option.systemImage, isSelected: intent == option,
                             identifier: "intent-\(option.rawValue)") {
                            select(option)
                        }
                    }
                }
                .padding(.top, 24)

                if let intent, !intent.refinements.isEmpty || intent.supportsLateNight {
                    refinementSection(for: intent)
                        .padding(.top, 28)
                        .transition(.opacity)
                }

            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .animation(AnimationProfile.selection.animation(reduceMotion: reduceMotion), value: intent)
        }
        .scrollIndicators(.hidden)
        // Pinned so "Find spots" is reachable in the medium detent.
        .safeAreaInset(edge: .bottom) {
            findSpotsButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(AppTheme.sheetSurface)
        }
        .background(AppTheme.sheetSurface)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .presentationContentInteraction(.resizes)
    }

    @ViewBuilder
    private func refinementSection(for intent: FeedIntent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(intent == .food ? "How long have you got?" : "Make it…")
                .font(AppTheme.caption)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
            ChipFlow(spacing: 8) {
                ForEach(intent.refinements) { option in
                    chip(option.label, isSelected: refinement == option,
                         identifier: "refinement-\(option.label)") {
                        Haptics.light()
                        refinement = option
                    }
                }
                if intent.supportsLateNight {
                    chip(FeedIntent.lateNight.title, systemImage: FeedIntent.lateNight.systemImage,
                         isSelected: lateNight, identifier: "modifier-late-night") {
                        Haptics.light()
                        lateNight.toggle()
                    }
                    .accessibilityValue(lateNight ? "On" : "Off")
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard let intent else { return false }
        return intent.refinements.isEmpty || refinement != nil
    }

    /// Direct-submit intents spend a discovery, so they need somewhere real to
    /// search first; the food-step intents ask later.
    private var needsLocationFirst: Bool {
        guard let intent else { return false }
        return intent.submitsDirectly && !viewModel.hasUsableLocation
    }

    private var findSpotsButton: some View {
        VStack(spacing: 10) {
            Button {
                guard let intent, canSubmit else { return }
                Haptics.medium()
                viewModel.applyIntent(intent, refinement: refinement, lateNight: lateNight)
            } label: {
                HStack(spacing: 8) {
                    Text("Find spots")
                        .font(AppTheme.headline)
                    Image(systemName: "arrow.right")
                        .font(AppTheme.label)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(AppTheme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AppTheme.sage)
                .clipShape(Capsule())
            }
            .buttonStyle(ScalePress())
            .disabled(!canSubmit || needsLocationFirst)
            .opacity(canSubmit && !needsLocationFirst ? 1 : 0.4)
            .accessibilityIdentifier("intent-find-spots")

            if needsLocationFirst {
                Text("Set your search area with the chip above first.")
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity)
            } else if intent?.submitsDirectly == true, let status = viewModel.discoveryAllowanceStatus {
                Text("Uses a discovery · \(status)")
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.accentInk)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("intent-allowance-status")
            }
        }
    }

    private func select(_ option: FeedIntent) {
        Haptics.light()
        guard intent != option else { return }
        intent = option
        refinement = option.defaultRefinement
        lateNight = false
        // Refinement chips sit below the medium detent; grow so they're visible.
        if !option.refinements.isEmpty || option.supportsLateNight { detent = .large }
    }

    private func chip(_ title: String, systemImage: String? = nil, isSelected: Bool,
                      identifier: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTheme.label)
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.primaryInk)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AppTheme.label)
                    .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.onSurface)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(isSelected ? AppTheme.sage : AppTheme.white)
            .clipShape(Capsule())
            .shadow(color: AppTheme.shadowColor, radius: 8, x: 0, y: 3)
            .animation(AnimationProfile.selection.animation(reduceMotion: reduceMotion), value: isSelected)
        }
        .buttonStyle(ScalePress())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Wraps chips onto as many rows as they need, so long labels and large
/// Dynamic Type sizes never truncate.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
