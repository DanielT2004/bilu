//
//  Recommendation.swift
//  bilu
//

import Foundation

struct Recommendation: Codable {
    let name: String
    let dish: String
    let image: String
    let explanation: String
    let mapsUrl: String
}

struct VibeResult: Codable {
    let recommendations: [Recommendation]
}
