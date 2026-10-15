//
//  EditProfileView.swift
//  bilu
//

import SwiftUI

/// Sheet to edit the local profile: display name + emoji avatar. Binds to the
/// ProfileViewModel draft fields so a cancel (swipe-down) discards uncommitted edits.
struct EditProfileView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0
    @FocusState private var nameFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            grabber
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    avatarPreview

                    section("Your name") {
                        TextField("e.g. Daniel", text: $viewModel.draftName)
                            .accessibilityLabel("Your name")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.onSurface)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.ghostBorder, lineWidth: nameFocused ? 1 : 0)
                            )
                    }

                    section("Pick an avatar") {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(ProfileAvatar.options, id: \.self) { emoji in
                                avatarButton(emoji)
                            }
                        }
                    }

                    saveButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
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

    /// A visible way out besides swiping down. "Done" keeps the edits, matching
    /// the Save button; swiping down still discards them.
    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                nameFocused = false
                viewModel.commitProfile()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Saves your name and avatar")
        }
        .padding(.horizontal, 16)
    }

    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(AppTheme.sageLt)
                .frame(width: 96, height: 96)
            Text(viewModel.draftAvatar)
                .font(.system(size: 46))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .accessibilityHidden(true)
    }

    private func avatarButton(_ emoji: String) -> some View {
        let isSelected = viewModel.draftAvatar == emoji
        return Button {
            Haptics.light()
            withAnimation(AnimationProfile.fastFeedback.animation(reduceMotion: reduceMotion)) {
                viewModel.draftAvatar = emoji
            }
        } label: {
            Text(emoji)
                .font(.system(size: 26))
                .frame(width: 46, height: 46)
                .background(isSelected ? AppTheme.sageLt : AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // Non-colour cue for the selected avatar (P1-4).
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.onPrimary, AppTheme.sage)
                            .offset(x: 5, y: -5)
                            .accessibilityHidden(true)
                    }
                }
                .scaleEffect(isSelected ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Avatar \(emoji)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var saveButton: some View {
        Button {
            nameFocused = false
            viewModel.commitProfile()
        } label: {
            Text("Save")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppTheme.sage)
                .clipShape(Capsule())
        }
        .buttonStyle(ScalePress())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
