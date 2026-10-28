//
//  Item.swift
//  DemonicTikTokList
//
//  Created by David Martens on 28.10.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
