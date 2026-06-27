//
//  Item.swift
//  NemoLoop
//
//  Created by GaoZimeng on 2026/6/28.
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
