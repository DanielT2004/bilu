//
//  DietaryPreferencesView.swift
//  bilu
//

import SwiftUI

/// Sheet to set dietary preferences (halal-only, vegan, etc.). Multi-select chips.
/// Selections persist immediately via the ProfileViewModel (no explicit save needed).
struct DietaryPreferencesView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            grabber
            topBar

            VStack(alignment: .leading, spacing: 8) {
                Text("Dietary preferences")
                    .font(AppTheme.display)
                    .foregroundStyle(AppTheme.onSurface)
                    .accessibilityAddTraits(.isHeader)
                Text("We'll keep these in mind for your recommendations.")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(DietaryPreference.allCases) { pref in
                        chip(pref)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.white.ignoresSafeArea())
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.translation.height > 0 { state = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        Haptics.medium()
                        dismiss()
                    }
                }
        )
    }

    private var grabber: some View {
        Capsule()
            .fill(AppTheme.subtle.opacity(0.4))
            .frame(width: 40, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    /// Choices save as they're tapped, so "Done" only closes the sheet.
    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func chip(_ pref: DietaryPreference) -> some View {
        let isOn = viewModel.dietary.contains(pref)
        return Button {
            withAnimation(AnimationProfile.fastFeedback.animation(reduceMotion: reduceMotion)) {
                viewModel.toggleDietary(pref)
            }
        } label: {
            HStack(spacing: 8) {
                Text(pref.emoji)
                    .font(.system(size: 16))
                Text(pref.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn ? AppTheme.onPrimary : AppTheme.onSurface)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.onPrimary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 44)
            .background(isOn ? AppTheme.sage : AppTheme.surface)
            .clipShape(Capsule())
        }
        .buttonStyle(ScalePress())
        .accessibilityLabel(pref.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
