//
//  MLBCallupsApp.swift
//  MLBCallups
//
//  Created by Nicolas Richards on 2/20/26.
//

import SwiftUI

@main
struct MLBCallupsApp: App {

    init() {
        #if os(iOS)
        NotificationManager.shared.registerBackgroundTask()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if os(iOS)
                    NotificationManager.shared.requestPermission()
                    NotificationManager.shared.scheduleNextRefresh()
                    #endif
                }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}
