//
//  Recommendation.swift
//  bilu
//

import Foundation

struct Recommendation: Codable, Identifiable {
    var id: String { name + dish }
    let name: String
    let dish: String
    let image: String?
    let explanation: String
    let mapsUrl: String
    let latitude: Double?
    let longitude: Double?
    let rating: Double?
    let reviewCount: Int?
    let isOpen: Bool?
    let photos: [String]?
    let address: String?
    let phone: String?
    let website: String?
    let placeId: String?
    let photoRefs: [String]?
}

struct VibeResult: Codable {
    let recommendations: [Recommendation]
    let groundingPlaces: [GroundingPlace]?
    let relaxed: Bool?
}

struct GroundingPlace: Codable {
    let placeId: String
    let title: String
    let uri: String
}
