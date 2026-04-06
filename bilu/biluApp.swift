//
//  biluApp.swift
//  bilu
//

import SwiftUI

@main
struct biluApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(hex: "f0ede6").ignoresSafeArea()
                HomeView()
            }
        }
    }
}
