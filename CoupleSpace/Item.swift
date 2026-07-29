//
//  Item.swift
//  CoupleSpace
//
//  Created by titus on 2026/7/29.
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
