//
//  biluApp.swift
//  bilu
//
//  Created by Danny on 3/13/26.
//

import SwiftUI

@main
struct biluApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
               
                HomeView()
            }
            .ignoresSafeArea(.all)
        }
    }
}
