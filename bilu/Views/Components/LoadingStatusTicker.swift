//
//  LoadingStatusTicker.swift
//  bilu
//

import SwiftUI
import Combine

private let C = AppTheme.self

/// Performative loading ticker: rotates through a casual, conversational stage list
/// while a real number from the loaded videos animates up. Used during the location
/// extraction wait (~5–10s after TikTok videos arrive).
struct LoadingStatusTicker: View {
    let videos: [TikTokVideo]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stageIndex = 0
    @State private var displayedCounter = 0
    @State private var dotPulse = false

    private let timer = Timer.publish(every: 2.4, on: .main, in: .common).autoconnect()

    private struct Stage {
        let text: String
        let counterTarget: Int?
        let counterUnit: String?
    }

    private var stages: [Stage] {
        let totalChars = videos.reduce(0) { $0 + $1.desc.count }
        let totalViews = videos.reduce(0) { $0 + $1.viewCount }
        return [
            Stage(text: "ok give me a sec, pulling the vids…",
                  counterTarget: videos.count, counterUnit: "videos"),
            Stage(text: "reading what creators are saying…",
                  counterTarget: totalChars, counterUnit: "chars"),
            Stage(text: "checking who's actually visited these spots…",
                  counterTarget: totalViews, counterUnit: "views"),
            Stage(text: "cross-checking with google…",
                  counterTarget: nil, counterUnit: nil),
            Stage(text: "ranking by who agrees…",
                  counterTarget: nil, counterUnit: nil),
            Stage(text: "almost done, polishing the map…",
                  counterTarget: nil, counterUnit: nil),
        ]
    }

    private var currentStage: Stage { stages[min(stageIndex, stages.count - 1)] }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(C.sage)
                .frame(width: 7, height: 7)
                .opacity(reduceMotion || dotPulse ? 1.0 : 0.35)
                .scaleEffect(reduceMotion || dotPulse ? 1.0 : 0.85)
                .accessibilityHidden(true)
                .onAppear {
                    // Reduce Motion: a steady dot instead of an endless pulse.
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        dotPulse = true
                    }
                }

            Text(currentStage.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(C.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                .id("stage-\(stageIndex)")

            Spacer(minLength: 6)

            if let unit = currentStage.counterUnit {
                Text("\(formatted(displayedCounter)) \(unit)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(C.onSurface)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: C.shadowColor, radius: 8, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(currentStage.text)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear { animateCounterToCurrentTarget() }
        .onReceive(timer) { _ in advanceStage() }
    }

    private func advanceStage() {
        guard stageIndex < stages.count - 1 else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            stageIndex += 1
        }
        animateCounterToCurrentTarget()
    }

    private func animateCounterToCurrentTarget() {
        guard let target = currentStage.counterTarget else {
            displayedCounter = 0
            return
        }
        if reduceMotion {
            displayedCounter = target
            return
        }
        displayedCounter = 0
        withAnimation(.easeOut(duration: 0.85)) {
            displayedCounter = target
        }
    }

    private func formatted(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        } else {
            return "\(n)"
        }
    }
}
