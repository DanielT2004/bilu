//
//  Recommendation.swift
//  bilu
//

import Foundation

struct Recommendation: Codable {
    let name: String
    let dish: String
    let image: String?
    let explanation: String
    let mapsUrl: String
    let latitude: Double?
    let longitude: Double?
}

struct VibeResult: Codable {
    let recommendations: [Recommendation]
    let groundingPlaces: [GroundingPlace]?
}

struct GroundingPlace: Codable {
    let placeId: String
    let title: String
    let uri: String
}
