//
//  Playable.swift
//  CachingPlayerItem_Example
//
//  Created by Gorjan Shukov on 10/24/20.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import Foundation

// Example protocol.
protocol Playable {
    var id: String { get }
    var streamURL: URL { get }
    var fileExtension: String { get }
}
