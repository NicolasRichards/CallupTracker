//
//  CallupWidgetBundle.swift
//  CallupWidget
//
//  Created by Nicolas Richards on 5/1/26.
//

import WidgetKit
import SwiftUI

@main
struct CallupWidgetBundle: WidgetBundle {
    var body: some Widget {
        CallupWidget()
        CallupWidgetControl()
        CallupWidgetLiveActivity()
    }
}
