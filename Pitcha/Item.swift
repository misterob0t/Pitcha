//
//  Item.swift
//  Pitcha
//
//  Created by Adil Aziz on 10/06/2026.
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
