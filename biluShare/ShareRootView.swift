import SwiftUI
import UIKit

struct ShareRootView: View {
    let sharedURL: URL?
    let onDone: () -> Void
    let onCancel: () -> Void

    @GestureState private var dragOffset: CGFloat = 0
    @State private var didFireThresholdHaptic = false
    @State private var appeared = false

    private let dismissThreshold: CGFloat = 120

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                Spacer()
                card
                    .offset(y: max(0, dragOffset))
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                if value.translation.height > 0 {
                                    state = value.translation.height
                                }
                            }
                            .onChanged { value in
                                if value.translation.height > dismissThreshold && !didFireThresholdHaptic {
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    didFireThresholdHaptic = true
                                } else if value.translation.height <= dismissThreshold {
                                    didFireThresholdHaptic = false
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > dismissThreshold {
                                    onCancel()
                                }
                            }
                    )
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: appeared)
        .onAppear { appeared = true }
    }

    private var card: some View {
        VStack(spacing: 24) {
            grabber

            header

            loaderBlock

            urlPreview

            doneButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(ShareTheme.surface)
        )
        .shadow(color: ShareTheme.shadowColor, radius: 28, x: 0, y: -4)
    }

    private var grabber: some View {
        Capsule()
            .fill(ShareTheme.subtle.opacity(0.35))
            .frame(width: 44, height: 5)
            .padding(.top, 8)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("bilu")
                .font(.custom("Georgia", size: 28))
                .foregroundColor(ShareTheme.onSurface)

            Text("Saved from TikTok")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(ShareTheme.muted)
        }
    }

    private var loaderBlock: some View {
        VStack(spacing: 16) {
            ShareLoader()

            Text("Got it. We'll find this spot.")
                .font(.custom("Georgia", size: 20))
                .multilineTextAlignment(.center)
                .foregroundColor(ShareTheme.onSurface)
                .padding(.horizontal, 12)
        }
    }

    private var urlPreview: some View {
        Group {
            if let url = sharedURL {
                Text(url.absoluteString)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(ShareTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ShareTheme.white)
                    )
            } else {
                Text("No link found")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ShareTheme.subtle)
                    .padding(.vertical, 10)
            }
        }
    }

    private var doneButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDone()
        } label: {
            Text("Done")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(ShareTheme.sage)
                .clipShape(Capsule())
        }
        .buttonStyle(SharePressStyle())
    }
}

private struct SharePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
