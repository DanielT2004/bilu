//
//  LocationChip.swift
//  bilu
//
//  "Near you · 2 mi" or the city name. Tapping opens the existing
//  HomeMapWidget in a large sheet; its callbacks still write to
//  `viewModel.selection`.
//

import SwiftUI

struct LocationChip: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var isShowingMap = false

    var body: some View {
        Button {
            Haptics.light()
            isShowingMap = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.sage)
                    .accessibilityHidden(true)
                Text(viewModel.locationChipLabel)
                    .font(AppTheme.label)
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(AppTheme.white)
            .clipShape(Capsule())
            .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(ScalePress())
        .accessibilityLabel("Search area, \(viewModel.locationChipLabel)")
        .accessibilityHint("Opens the map to change where bilu searches")
        .accessibilityIdentifier("feed-location-chip")
        .sheet(isPresented: $isShowingMap) {
            LocationSheet(viewModel: viewModel)
        }
    }
}

/// The map sheet behind the chip. The widget is always expanded here, so the
/// user can drag the pin and radius right away.
private struct LocationSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Where to search")
                    .font(AppTheme.title)
                    .foregroundStyle(AppTheme.onSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    Haptics.light()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(AppTheme.label)
                        .foregroundStyle(AppTheme.sage)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("location-sheet-done")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            HomeMapWidget(
                locationLabel: viewModel.mapLocationLabel,
                initialCenter: viewModel.feedOrigin,
                isExpanded: $isExpanded,
                staysExpanded: true,
                initialRadiusMiles: viewModel.selection.radiusMiles,
                initialUseRadius: viewModel.selection.useRadiusSearch,
                onRadiusChanged: { miles, coord in
                    viewModel.selection.radiusMiles = miles
                    viewModel.selection.latitude = coord.latitude
                    viewModel.selection.longitude = coord.longitude
                    viewModel.selection.useRadiusSearch = true
                },
                onLocationResolved: { label in
                    viewModel.detectedLocation = label
                    viewModel.selection.location = label
                },
                onRadiusModeChanged: { isRadiusMode in
                    viewModel.selection.useRadiusSearch = isRadiusMode
                    if !isRadiusMode {
                        viewModel.selection.latitude = nil
                        viewModel.selection.longitude = nil
                    }
                }
            )

            Spacer(minLength: 0)
        }
        .background(AppTheme.surface)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }
}
