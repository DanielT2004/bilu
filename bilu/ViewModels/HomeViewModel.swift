//
//  HomeViewModel.swift
//  bilu
//

import Foundation
import Combine

enum Step: String, CaseIterable {
    case occasion
    case vibe
    case hunger
    case location
    case survey
    case loading
    case reveal
}

struct VibeOption {
    let key: String
    let displayTitle: String
    let desc: String
    let systemImage: String
}

struct HungerOption {
    let key: String
    let displayTitle: String
    let desc: String
    let systemImage: String
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var step: Step = .occasion
    @Published var selection: VibeSelection
    @Published var recommendations: [Recommendation] = []
    @Published var loadingPhase: String = "Using AI to search"

    init() {
        self.selection = VibeSelection()
    }

    func handleOccasion(_ occasion: String) {
        selection.occasion = occasion
        selection.vibe = []
        selection.hunger = []
        selection.location = ""
        step = .vibe
    }

    func toggleVibe(_ key: String) {
        if selection.vibe.contains(key) {
            selection.vibe.removeAll { $0 == key }
        } else {
            selection.vibe.append(key)
        }
    }

    func toggleHunger(_ key: String) {
        if selection.hunger.contains(key) {
            selection.hunger.removeAll { $0 == key }
        } else {
            selection.hunger.append(key)
        }
    }

    func reset() {
        step = .occasion
        selection = VibeSelection()
        recommendations = []
    }

    func submitSurvey() async {
        step = .loading
        loadingPhase = "Using AI to search"

        recommendations = await GeminiService.getVibeRecommendations(selection: selection)
        step = .reveal
    }

    var vibesForOccasion: [VibeOption] {
        switch selection.occasion {
        case "Grab & Go":
            return [
                VibeOption(key: "Trending", displayTitle: "Trending", desc: "Viral & Trending", systemImage: "chart.line.uptrend.xyaxis"),
                VibeOption(key: "Local and authentic", displayTitle: "Local and authentic", desc: "Elite flavor, no lines", systemImage: "diamond")
            ]
        case "Happy Hour":
            return [
                VibeOption(key: "The Social Buzz", displayTitle: "The Social Buzz", desc: "Networking & High Energy", systemImage: "wineglass"),
                VibeOption(key: "The Chill Vibe", displayTitle: "The Chill Vibe", desc: "Low-Key & Relaxed", systemImage: "sofa"),
                VibeOption(key: "The Activity Hub", displayTitle: "The Activity Hub", desc: "Games & Trivia", systemImage: "flag"),
                VibeOption(key: "The Sunset View", displayTitle: "The Sunset View", desc: "Outdoor & Patios", systemImage: "sun.max")
            ]
        case "Sit Down":
            return [
                VibeOption(key: "The Aesthetic", displayTitle: "Aesthetic", desc: "Peak visuals", systemImage: "camera"),
                VibeOption(key: "Dim & Intimate", displayTitle: "Intimate", desc: "Mood lighting", systemImage: "moon"),
                VibeOption(key: "Trendy & Viral", displayTitle: "Trendy", desc: "The 'It' spot", systemImage: "chart.line.uptrend.xyaxis"),
                VibeOption(key: "Nothing Fancy", displayTitle: "Authentic", desc: "Nothing fancy", systemImage: "person")
            ]
        default:
            return []
        }
    }

    var hungerForOccasion: [HungerOption] {
        switch selection.occasion {
        case "Grab & Go":
            return [
                HungerOption(key: "Warm & Slurpy", displayTitle: "Warm & Slurpy", desc: "Ramen, Pasta, Pho", systemImage: "leaf"),
                HungerOption(key: "Doughy & Loaded", displayTitle: "Doughy & Loaded", desc: "Burgers, Pizza, Burritos", systemImage: "leaf"),
                HungerOption(key: "Fresh & Crisp", displayTitle: "Fresh & Crisp", desc: "Sushi, Mediterranean", systemImage: "leaf"),
                HungerOption(key: "Spicy & Bold", displayTitle: "Spicy & Bold", desc: "Nashville Hot, Thai", systemImage: "flame"),
                HungerOption(key: "Small & Shared", displayTitle: "Small & Shared", desc: "Tapas, Dim Sum, Bites", systemImage: "person.2"),
                HungerOption(key: "Sweet & Treat", displayTitle: "Sweet & Treat", desc: "Desserts, Pastries", systemImage: "leaf")
            ]
        case "Happy Hour":
            return [
                HungerOption(key: "The Shareable Feast", displayTitle: "The Shareable Feast", desc: "Tapas & Small Plates", systemImage: "person.2"),
                HungerOption(key: "The Sip & Snack", displayTitle: "The Sip & Snack", desc: "Bar Bites & Salty Hits", systemImage: "cup.and.saucer"),
                HungerOption(key: "The Half-Priced Hero", displayTitle: "The Half-Priced Hero", desc: "Mini Versions of Classics", systemImage: "leaf"),
                HungerOption(key: "The Liquid Dinner", displayTitle: "The Liquid Dinner", desc: "Drink Flights & Cocktails", systemImage: "wineglass")
            ]
        case "Sit Down":
            return [
                HungerOption(key: "Warm & Slurpy", displayTitle: "Warm & Slurpy", desc: "Pasta, Ramen, Pho", systemImage: "leaf"),
                HungerOption(key: "Doughy & Loaded", displayTitle: "Doughy & Loaded", desc: "Burgers, Pizza, Steaks", systemImage: "leaf"),
                HungerOption(key: "Fresh & Crisp", displayTitle: "Fresh & Crisp", desc: "Sushi, Salads, Bowls", systemImage: "leaf"),
                HungerOption(key: "Spicy & Bold", displayTitle: "Spicy & Bold", desc: "Thai, Szechuan, Hot", systemImage: "flame")
            ]
        default:
            return []
        }
    }

    var progressStepIndex: Int? {
        Self.stepsForProgress.firstIndex { $0.id == step }
    }

    static let stepsForProgress: [(id: Step, label: String)] = [
        (.occasion, "THE CLOCK"),
        (.vibe, "THE VIBE"),
        (.hunger, "THE HUNGER"),
        (.location, "THE AREA"),
        (.survey, "OPTIONS")
    ]
}
