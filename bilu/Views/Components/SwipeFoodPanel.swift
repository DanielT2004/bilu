//
//  SwipeFoodPanel.swift
//  bilu
//
//  Inline photo-grid panel for food sub-options. A 2×2 grid of real food
//  photos with single-tap multi-select. Drops in below an expanded food
//  category row on the food-feeling step.
//

import SwiftUI

struct SwipeFoodPanel: View {
    let category: FoodCategoryOption
    let selectedKeys: [String]
    let onToggle: (FoodSubOption) -> Void
    let onClose: () -> Void

    private var deck: [FoodSubOption] { category.subOptions }
    private var pickedCount: Int { deck.filter { selectedKeys.contains($0.key) }.count }

    private let tileAspect: CGFloat = 1.05
    private let gridSpacing: CGFloat = 10

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: gridSpacing),
            GridItem(.flexible(), spacing: gridSpacing)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            grid
                .padding(.top, 14)
            footerHint
                .padding(.top, 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 18, x: 0, y: 6)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
            removal:   .opacity
        ))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(category.emoji).font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text("PICK ANY THAT LOOK GOOD")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(AppTheme.muted)
                Text(category.title)
                    .font(AppTheme.title)
                    .italic()
                    .foregroundColor(AppTheme.onSurface)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if pickedCount > 0 {
                Text("\(pickedCount) picked")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.sage)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.onSurface)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pickedCount)
    }

    // MARK: - 2-column photo grid

    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
            ForEach(deck, id: \.key) { item in
                photoTile(item)
            }
        }
    }

    @ViewBuilder
    private func photoTile(_ item: FoodSubOption) -> some View {
        let isPicked = selectedKeys.contains(item.key)
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                onToggle(item)
            }
        }) {
            // Color.clear is the sizer: it has no intrinsic size, so the aspect
            // ratio is enforced purely from the proposed width. The real tile
            // content sits in the overlay and inherits this exact frame, so
            // photos with different intrinsic dimensions can't leak their
            // size up and produce uneven tiles.
            Color.clear
                .aspectRatio(tileAspect, contentMode: .fit)
                .overlay(
                    ZStack(alignment: .bottomLeading) {
                        photoFill(for: item)
                        bottomGradient
                        labelStack(for: item)
                        if isPicked {
                            pickedCheckmark
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: .topTrailing)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isPicked ? AppTheme.sage : Color.clear,
                                lineWidth: isPicked ? 3 : 0)
                )
                .shadow(color: isPicked ? AppTheme.sage.opacity(0.30) : AppTheme.shadowColor,
                        radius: isPicked ? 14 : 8, x: 0, y: isPicked ? 6 : 3)
                .scaleEffect(isPicked ? 1.015 : 1.0)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPicked)
        }
        .buttonStyle(TilePress())
    }

    @ViewBuilder
    private func photoFill(for item: FoodSubOption) -> some View {
        if let urlString = item.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    ZStack {
                        AppTheme.surface
                        Text(item.emoji).font(.system(size: 40)).opacity(0.6)
                    }
                case .failure:
                    ZStack {
                        AppTheme.surface
                        Text(item.emoji).font(.system(size: 56))
                    }
                @unknown default:
                    AppTheme.surface
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                AppTheme.surface
                Text(item.emoji).font(.system(size: 56))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bottomGradient: some View {
        LinearGradient(
            colors: [AppTheme.onSurface.opacity(0.0), AppTheme.onSurface.opacity(0.55)],
            startPoint: .center, endPoint: .bottom
        )
    }

    private func labelStack(for item: FoodSubOption) -> some View {
        HStack(spacing: 6) {
            Text(item.emoji)
                .font(.system(size: 16))
            Text(item.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var pickedCheckmark: some View {
        ZStack {
            Circle()
                .fill(AppTheme.sage)
                .frame(width: 26, height: 26)
                .shadow(color: AppTheme.sage.opacity(0.4), radius: 6, x: 0, y: 2)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(.white)
        }
        .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    // MARK: - Footer hint

    private var footerHint: some View {
        Text(pickedCount == 0
             ? "Tap any photo to pick · pick more than one if you can't decide"
             : "Tap to add or remove · all your picks help us narrow it down")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(AppTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
