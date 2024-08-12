# CachingPlayerItem

CachingPlayerItem is a subclass of AVPlayerItem that lets you stream and cache media content on iOS. Initial idea for this library was found [here](https://github.com/neekeetab/CachingPlayerItem).

[![CI Status](https://img.shields.io/travis/sukov/CachingPlayerItem.svg?style=flat)](https://travis-ci.org/sukov/CachingPlayerItem)
[![Version](https://img.shields.io/cocoapods/v/CachingPlayerItem.svg?style=flat)](https://cocoapods.org/pods/CachingPlayerItem)
[![License](https://img.shields.io/cocoapods/l/CachingPlayerItem.svg?style=flat)](https://cocoapods.org/pods/CachingPlayerItem)
[![Language Swift](https://img.shields.io/badge/Language-Swift%205.0-orange.svg?style=flat)](https://swift.org)
[![Platform](https://img.shields.io/cocoapods/p/CachingPlayerItem.svg?style=flat)](https://cocoapods.org/pods/CachingPlayerItem)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat)](https://www.swift.org/package-manager)

## Features

- [x] Playing and caching remote media
- [x] Downloaded data is buffered and stored on a file, therefore you won't have any RAM memory issues
- [x] Playing from a local file / data
- [x] Convenient notifications through `CachingPlayerItemDelegate` delegate
- [x] `CachingPlayerItem` is a subclass of `AVPlayerItem`, so you can use it in the same manner as `AVPlayerItem` and take the full advantage of `AVFoundation` Framework
- [x] Configurable downloadBufferLimit / readDataLimit through `CachingPlayerItemConfiguration`
- [x] Play remote media without caching and still make use of `CachingPlayerItemDelegate`
- [x] [Complete Documentation](https://sukov.github.io/CachingPlayerItem/)

## Requirements

- iOS 10.0+ 
- Xcode 12.0+
- Swift 5.0+

## Installation

### CocoaPods

[CocoaPods](http://cocoapods.org) is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

To integrate CachingPlayerItem into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '10.0'
use_frameworks!

target '<Your Target Name>' do
    pod 'CachingPlayerItem'
end
```
### Swift Package Manager

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler. 

Once you have your Swift package set up, adding `CachingPlayerItem` as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift`.

```swift
dependencies: [
    .package(url: "https://github.com/sukov/CachingPlayerItem.git", from: "1.0.5")
]
```

## Usage

### Quick Start

```Swift
import UIKit
import AVFoundation
import CachingPlayerItem

class ViewController: UIViewController {
    // You need to keep a strong reference to your player.
    var player: AVPlayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
     
        let url = URL(string: "https://random-url.com/video.mp4")!
        let playerItem = CachingPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.play()
        
    }
}
```
**From Apple docs: It's strongly recommended to set AVPlayer's property `automaticallyWaitsToMinimizeStalling` to `false`. Not doing so can lead to poor startup times for playback and poor recovery from stalls.**

If you want to cache a file without playing it, or to preload it for future playing, use `download()` method:
```Swift
let playerItem = CachingPlayerItem(url: videoURL)
playerItem.download()
```
It's fine to start playing the item while it's being downloaded.

### CachingPlayerItemDelegate protocol

Note: All of the methods are optional.

```Swift
@objc public protocol CachingPlayerItemDelegate {
    // MARK: Downloading delegate methods

    /// Called when the media file is fully downloaded.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingFileAt filePath: String)

    /// Called every time a new portion of data is received.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int)

    /// Called on downloading error.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error)

    // MARK: Playing delegate methods

    /// Called after initial prebuffering is finished, means we are ready to play.
    @objc optional func playerItemReadyToPlay(_ playerItem: CachingPlayerItem)

    /// Called when the player is unable to play the data/url.
    @objc optional func playerItemDidFailToPlay(_ playerItem: CachingPlayerItem, withError error: Error?)

    /// Called when the data being downloaded did not arrive in time to continue playback.
    @objc optional func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem)
}
```

**Important**: You are in charge for managing the downloaded local media files. In case you used an initializer that generates the filePath randomly, you will be able to retrieve it in `didFinishDownloadingFileAt` delegate method.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Author

sukov, gorjan5@hotmail.com

## License

CachingPlayerItem is available under the MIT license. See the LICENSE file for more info.

## Known limitations

- CachingPlayerItem loads its content sequentially. If you seek to yet not downloaded portion, it waits until data previous to this position is downloaded, and only then starts the playback.
- URL's must contain a file extension for the player to load properly. To get around this, a custom file extension can be specified e.g. `let playerItem = CachingPlayerItem(url: url, customFileExtension: "mp3")`.
- HTTP live streaming (HLS) `M3U8` caching is not supported. You can only use `init(nonCachingURL:)` for playing M3U8.
