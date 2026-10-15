//
//  ProfileSegmentedControl.swift
//  bilu
//

import SwiftUI

/// A pill segmented control with a sliding active pill (matchedGeometryEffect).
/// No Picker chrome, no borders — pure tonal shapes per the design system.
struct ProfileSegmentedControl: View {
    @Binding var selection: SavedListType
    let savedCount: Int
    let wantToGoCount: Int

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            segment(.saved, title: "Saved", count: savedCount)
            segment(.wantToGo, title: "Want to Go", count: wantToGoCount)
        }
        .padding(5)
        .background(AppTheme.neutralBg)
        .clipShape(Capsule())
    }

    private func segment(_ type: SavedListType, title: String, count: Int) -> some View {
        let isActive = selection == type
        return Button {
            guard !isActive else { return }
            Haptics.light()
            withAnimation(AnimationProfile.selection.animation(reduceMotion: reduceMotion)) {
                selection = type
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isActive ? .white.opacity(0.85) : AppTheme.subtle)
            }
            .foregroundStyle(isActive ? .white : AppTheme.muted)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Capsule())
            .background {
                if isActive {
                    Capsule()
                        .fill(AppTheme.sage)
                        .matchedGeometryEffect(id: "activePill", in: pill)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(count == 1 ? "1 place" : "\(count) places")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
