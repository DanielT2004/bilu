//
//  SearchLocation.swift
//  bilu
//

import Foundation

struct SearchLocation: Identifiable, Codable, Equatable {
    let placeId: String
    let placeName: String
    let address: String
    let lat: Double
    let lng: Double
    let rank: Int
    let totalViews: Int
    let videoIds: [String]

    var id: String { placeId }

    /// The top 3 places get prominent pins
    var isTopRanked: Bool { rank < 3 }
}
