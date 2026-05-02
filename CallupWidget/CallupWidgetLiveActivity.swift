//
//  CallupWidgetLiveActivity.swift
//  CallupWidget
//
//  Created by Nicolas Richards on 5/1/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct CallupWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct CallupWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallupWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension CallupWidgetAttributes {
    fileprivate static var preview: CallupWidgetAttributes {
        CallupWidgetAttributes(name: "World")
    }
}

extension CallupWidgetAttributes.ContentState {
    fileprivate static var smiley: CallupWidgetAttributes.ContentState {
        CallupWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: CallupWidgetAttributes.ContentState {
         CallupWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: CallupWidgetAttributes.preview) {
   CallupWidgetLiveActivity()
} contentStates: {
    CallupWidgetAttributes.ContentState.smiley
    CallupWidgetAttributes.ContentState.starEyes
}
