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
    @StateObject private var placeSearch = PlaceSearchModel()
    @State private var recenter: MapRecenterRequest?
    @FocusState private var searchFocused: Bool

    private var isShowingSuggestions: Bool {
        searchFocused && !placeSearch.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

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

            searchField
                .padding(.horizontal, 16)

            if let message = placeSearch.errorMessage {
                Text(message)
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 20)
            }

            // The map stays mounted under the suggestions so its pin, radius
            // and pending recenter survive while the user types.
            ZStack(alignment: .top) {
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
                },
                recenterRequest: recenter
            )
            .accessibilityHidden(isShowingSuggestions)

                if isShowingSuggestions {
                    suggestionList
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(AppTheme.surface)
                }
            }

            Spacer(minLength: 0)
        }
        .background(AppTheme.surface)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(AppTheme.label)
                .foregroundStyle(searchFocused ? AppTheme.sage : AppTheme.muted)
                .accessibilityHidden(true)
            TextField("Search a city, neighborhood or address", text: $placeSearch.query)
                .font(AppTheme.body)
                .foregroundStyle(AppTheme.onSurface)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit {
                    if let first = placeSearch.suggestions.first { pick(first) }
                }
                .accessibilityLabel("Search for a place")
                .accessibilityIdentifier("location-search-field")
            if placeSearch.isResolving {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else if !placeSearch.query.isEmpty {
                Button {
                    Haptics.light()
                    placeSearch.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.subtle)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 44)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if placeSearch.suggestions.isEmpty {
                    Text("Keep typing to see places")
                        .font(AppTheme.body)
                        .foregroundStyle(AppTheme.muted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                ForEach(placeSearch.suggestions) { suggestion in
                    Button { pick(suggestion) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.sage)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(AppTheme.body)
                                    .foregroundStyle(AppTheme.onSurface)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle)
                                        .font(AppTheme.caption)
                                        .foregroundStyle(AppTheme.muted)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(placeSearch.isResolving)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Searches around this place")
                    .accessibilityIdentifier("location-suggestion-\(suggestion.id)")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Moves the map to the picked place; the map's own geocode then updates
    /// the label and search area exactly as a manual pan would.
    private func pick(_ suggestion: PlaceSuggestion) {
        Haptics.medium()
        Task {
            guard let coordinate = await placeSearch.resolve(suggestion) else { return }
            recenter = MapRecenterRequest(coordinate: coordinate)
            placeSearch.clear()
            searchFocused = false
        }
    }
}
