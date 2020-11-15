//
//  CachingPlayerItemConfiguration.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation

/// CachingPlayerItem global configuration.
public enum CachingPlayerItemConfiguration {
    /// How much data is downloaded in memory before stored on a file.
    public static var downloadBufferLimit: Int = 128.KB

    /// How much data is allowed to be read in memory at a time.
    public static var readDataLimit: Int = 10.MB
}

fileprivate extension Int {
    var KB: Int { return self * 1024 }
    var MB: Int { return self * 1024 * 1024 }
}

