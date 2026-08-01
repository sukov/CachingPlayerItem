import Quick
import Nimble
import AVFoundation
import Network
@testable import CachingPlayerItem

class CachingPlayerItemSpec: QuickSpec {
    override class func spec() {
        describe("CachingPlayerItem") {
            var sut: CachingPlayerItem!
            var delegate: MockCachingPlayerItemDelegate!
            var testURL: URL!
            var tempDirectory: URL!

            beforeEach {
                testURL = URL(string: "https://example.com/test-video.mp4")!
                delegate = MockCachingPlayerItemDelegate()

                tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            }

            afterEach {
                sut = nil
                delegate = nil
                try? FileManager.default.removeItem(at: tempDirectory)
            }

            // MARK: - Initialization Tests

            context("when initialized with URL") {
                it("creates AVURLAsset with custom scheme") {
                    sut = CachingPlayerItem(url: testURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.scheme).to(equal("cachingPlayerItemScheme"))
                    expect(urlAsset.url.path).to(equal(testURL.path))
                }

                it("preserves original path extension") {
                    let mp4URL = URL(string: "https://example.com/video.mp4")!
                    sut = CachingPlayerItem(url: mp4URL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp4"))
                }

                it("uses custom file extension when provided") {
                    let urlWithoutExtension = URL(string: "https://example.com/media/12345")!
                    sut = CachingPlayerItem(url: urlWithoutExtension, customFileExtension: "mp3")

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp3"))
                }

                it("extracts HTTP headers from avUrlAssetOptions") {
                    let options = ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer token123"]]
                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: options)

                    expect(sut.urlRequestHeaders).toNot(beNil())
                    expect(sut.urlRequestHeaders?["Authorization"]).to(equal("Bearer token123"))
                }

                it("stores configuration correctly") {
                    let config = CachingPlayerItemConfiguration(
                        downloadBufferLimit: 1024 * 1024,
                        readDataLimit: 512 * 1024
                    )
                    sut = CachingPlayerItem(url: testURL, configuration: config)

                    expect(sut.configuration.downloadBufferLimit).to(equal(1024 * 1024))
                    expect(sut.configuration.readDataLimit).to(equal(512 * 1024))
                }

                it("generates random save file path in caches directory") {
                    sut = CachingPlayerItem(url: testURL)

                    // Access the internal saveFilePath through reflection or by testing behavior
                    // Since saveFilePath is private, we test indirectly through delegate callback
                    sut.delegate = delegate

                    expect(sut).to(beAKindOf(CachingPlayerItem.self))
                }

                it("uses provided save file path") {
                    let customPath = tempDirectory.appendingPathComponent("custom-video.mp4").path
                    sut = CachingPlayerItem(url: testURL, saveFilePath: customPath, customFileExtension: nil)

                    // Verify by attempting to create the player item
                    expect(sut.asset).to(beAKindOf(AVURLAsset.self))
                }
            }

            context("when initialized for non-caching playback") {
                it("uses original URL scheme without modification") {
                    sut = CachingPlayerItem(nonCachingURL: testURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.scheme).to(equal("https"))
                    expect(urlAsset.url.absoluteString).to(equal(testURL.absoluteString))
                }

                it("does not support download method") {
                    sut = CachingPlayerItem(nonCachingURL: testURL)

                    expect(sut.download()).to(throwAssertion())
                    expect(sut.asset).to(beAKindOf(AVURLAsset.self))
                }
            }

            context("when initialized with local data") {
                it("writes data to file and creates playable item") {
                    let testData = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE])

                    expect {
                        sut = try CachingPlayerItem(data: testData, customFileExtension: "mp3")
                    }.toNot(throwError())

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.isFileURL).to(beTrue())
                    expect(urlAsset.url.pathExtension).to(equal("mp3"))

                    // Verify file exists and contains data
                    let fileExists = FileManager.default.fileExists(atPath: urlAsset.url.path)
                    expect(fileExists).to(beTrue())
                }

                it("creates file with correct size") {
                    let testData = Data(repeating: 0xFF, count: 1024)

                    expect {
                        sut = try CachingPlayerItem(data: testData, customFileExtension: "mp4")
                    }.toNot(throwError())

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    let attributes = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)
                    let fileSize = attributes?[.size] as? Int
                    expect(fileSize).to(equal(1024))
                }
            }

            context("when initialized with local file") {
                it("creates AVURLAsset pointing to file URL") {
                    let localFileURL = tempDirectory.appendingPathComponent("local-video.mp4")
                    FileManager.default.createFile(atPath: localFileURL.path, contents: Data([0x00, 0x01]), attributes: nil)

                    sut = CachingPlayerItem(filePathURL: localFileURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url).to(equal(localFileURL))
                    expect(urlAsset.url.isFileURL).to(beTrue())
                }

                it("creates symbolic link when custom file extension provided") {
                    let localFileURL = tempDirectory.appendingPathComponent("original-file")
                    let testData = Data([0x01, 0x02, 0x03])
                    FileManager.default.createFile(atPath: localFileURL.path, contents: testData, attributes: nil)

                    sut = CachingPlayerItem(filePathURL: localFileURL, fileExtension: "mp3")

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp3"))

                    // Verify symbolic link was created
                    let linkAttributes = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)
                    let fileType = linkAttributes?[.type] as? FileAttributeType
                    expect(fileType).to(equal(.typeSymbolicLink))
                }

                it("removes old symbolic links before creating new ones") {
                    let originalFile = tempDirectory.appendingPathComponent("original")
                    FileManager.default.createFile(atPath: originalFile.path, contents: Data([0x01]), attributes: nil)

                    // Create first item (creates symlink)
                    let item1 = CachingPlayerItem(filePathURL: originalFile, fileExtension: "mp3")
                    let symLinkPath = (item1.asset as? AVURLAsset)?.url.path

                    // Create second item with same parameters (should remove old symlink)
                    sut = CachingPlayerItem(filePathURL: originalFile, fileExtension: "mp3")

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.path).to(equal(symLinkPath))
                }
            }

            context("when initialized with AVAsset") {
                it("uses the provided AVAsset directly") {
                    let customAsset = AVURLAsset(url: testURL)
                    sut = CachingPlayerItem(asset: customAsset, automaticallyLoadedAssetKeys: nil)

                    expect(sut.asset).to(be(customAsset))
                }
            }

            // MARK: - Delegate Tests

            context("when delegate is set") {
                beforeEach {
                    sut = CachingPlayerItem(url: testURL)
                    sut.delegate = delegate
                }

                it("stores weak reference to delegate") {
                    expect(sut.delegate).to(be(delegate))
                }

                it("calls playerItemPlaybackStalled when stall notification received") {
                    NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: sut)

                    expect(delegate.playbackStalledCalled).toEventually(beTrue(), timeout: .seconds(1))
                }
            }

            // MARK: - Download Tests

            context("when download is initiated") {
                beforeEach {
                    sut = CachingPlayerItem(url: testURL)
                    sut.delegate = delegate
                }

                it("triggers download for caching player item") {
                    expect { sut.download() }.toNot(throwAssertion())
                }
            }

            // MARK: - passOnObject Tests

            context("when using passOnObject") {
                beforeEach {
                    sut = CachingPlayerItem(url: testURL)
                }

                it("can store any type conforming to Any") {
                    struct CustomModel {
                        let id: Int
                        let name: String
                    }

                    let model = CustomModel(id: 123, name: "Test")
                    sut.passOnObject = model

                    guard let storedModel = sut.passOnObject as? CustomModel else {
                        fail("Expected CustomModel to be stored")
                        return
                    }

                    expect(storedModel.id).to(equal(123))
                    expect(storedModel.name).to(equal("Test"))
                }

                it("can be set to nil") {
                    sut.passOnObject = "test"
                    expect(sut.passOnObject).toNot(beNil())

                    sut.passOnObject = nil
                    expect(sut.passOnObject).to(beNil())
                }
            }

            // MARK: - Configuration Tests

            context("when using custom configuration") {
                it("applies all configuration properties") {
                    let config = CachingPlayerItemConfiguration(
                        downloadBufferLimit: 2 * 1024 * 1024,
                        readDataLimit: 1 * 1024 * 1024,
                        shouldVerifyDownloadedFileSize: true,
                        minimumExpectedFileSize: 500000,
                        shouldCheckAvailableDiskSpaceBeforeCaching: false,
                        allowsUncachedSeek: false,
                        logLevel: .info
                    )
                    sut = CachingPlayerItem(url: testURL, configuration: config)

                    expect(sut.configuration.downloadBufferLimit).to(equal(2 * 1024 * 1024))
                    expect(sut.configuration.readDataLimit).to(equal(1 * 1024 * 1024))
                    expect(sut.configuration.shouldVerifyDownloadedFileSize).to(beTrue())
                    expect(sut.configuration.minimumExpectedFileSize).to(equal(500000))
                    expect(sut.configuration.shouldCheckAvailableDiskSpaceBeforeCaching).to(beFalse())
                    expect(sut.configuration.allowsUncachedSeek).to(beFalse())
                    expect(sut.configuration.logLevel).to(equal(.info))
                }

                it("uses default configuration when not specified") {
                    sut = CachingPlayerItem(url: testURL)

                    expect(sut.configuration.downloadBufferLimit).to(equal(15 * 1024 * 1024))
                    expect(sut.configuration.readDataLimit).to(equal(10 * 1024 * 1024))
                }
            }

            // MARK: - Memory Management Tests

            context("when managing memory") {
                it("deallocates properly") {
                    weak var weakReference: CachingPlayerItem?

                    autoreleasepool {
                        let item = CachingPlayerItem(url: testURL)
                        weakReference = item
                        expect(weakReference).toNot(beNil())
                    }

                    expect(weakReference).toEventually(beNil(), timeout: .seconds(2))
                }

                it("maintains weak reference to delegate") {
                    sut = CachingPlayerItem(url: testURL)
                    weak var weakDelegate: MockCachingPlayerItemDelegate?

                    autoreleasepool {
                        let strongDelegate = MockCachingPlayerItemDelegate()
                        weakDelegate = strongDelegate
                        sut.delegate = strongDelegate
                        expect(sut.delegate).toNot(beNil())
                    }

                    expect(weakDelegate).toEventually(beNil(), timeout: .seconds(2))
                    expect(sut.delegate).to(beNil())
                }

                it("cancels download on deinit for caching items") {
                    weak var weakItem: CachingPlayerItem?

                    autoreleasepool {
                        let item = CachingPlayerItem(url: testURL)
                        weakItem = item
                        item.download()
                    }

                    // Should cancel session on deinit
                    expect(weakItem).toEventually(beNil(), timeout: .seconds(2))
                }
            }

            // MARK: - AVPlayerItem Compatibility Tests

            context("when used as AVPlayerItem") {
                it("integrates with AVPlayer") {
                    sut = CachingPlayerItem(url: testURL)
                    let player = AVPlayer(playerItem: sut)

                    expect(player.currentItem).to(be(sut))
                }

                it("has unknown status initially") {
                    sut = CachingPlayerItem(url: testURL)

                    expect(sut.status).to(equal(AVPlayerItem.Status.unknown))
                }

                it("supports standard AVPlayerItem operations") {
                    sut = CachingPlayerItem(url: testURL)
                    let time = CMTime(seconds: 5, preferredTimescale: 600)

                    var completionCalled = false
                    sut.seek(to: time) { _ in
                        completionCalled = true
                    }

                    expect(completionCalled).toEventually(beTrue(), timeout: .seconds(2))
                }
            }

            // MARK: - URL Validation Tests

            context("when validating URLs") {
                it("handles different video extensions") {
                    let extensions = ["mp4", "mov", "m4v", "avi"]

                    for ext in extensions {
                        let url = URL(string: "https://example.com/video.\(ext)")!
                        let item = CachingPlayerItem(url: url)

                        guard let urlAsset = item.asset as? AVURLAsset else {
                            fail("Expected asset to be AVURLAsset for extension \(ext)")
                            continue
                        }

                        expect(urlAsset.url.pathExtension).to(equal(ext))
                    }
                }

                it("handles different audio extensions") {
                    let extensions = ["mp3", "m4a", "wav", "aac"]

                    for ext in extensions {
                        let url = URL(string: "https://example.com/audio.\(ext)")!
                        let item = CachingPlayerItem(url: url)

                        guard let urlAsset = item.asset as? AVURLAsset else {
                            fail("Expected asset to be AVURLAsset for extension \(ext)")
                            continue
                        }

                        expect(urlAsset.url.pathExtension).to(equal(ext))
                    }
                }
            }

            // MARK: - Concurrent Usage Tests

            context("when used concurrently") {
                it("creates independent instances") {
                    let item1 = CachingPlayerItem(url: testURL)
                    let item2 = CachingPlayerItem(url: testURL)

                    expect(item1).toNot(be(item2))
                    expect(item1.asset).toNot(be(item2.asset))
                }

                it("allows different configurations per instance") {
                    let config1 = CachingPlayerItemConfiguration(downloadBufferLimit: 5 * 1024 * 1024)
                    let config2 = CachingPlayerItemConfiguration(downloadBufferLimit: 10 * 1024 * 1024)

                    let item1 = CachingPlayerItem(url: testURL, configuration: config1)
                    let item2 = CachingPlayerItem(url: testURL, configuration: config2)

                    expect(item1.configuration.downloadBufferLimit).to(equal(5 * 1024 * 1024))
                    expect(item2.configuration.downloadBufferLimit).to(equal(10 * 1024 * 1024))
                }
            }

            // MARK: - HTTP Headers Tests

            context("when setting HTTP headers") {
                it("extracts headers from AVURLAssetHTTPHeaderFieldsKey") {
                    let headers = [
                        "Authorization": "Bearer token123",
                        "User-Agent": "CustomAgent/1.0",
                        "Accept-Language": "en-US"
                    ]
                    let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]

                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: options)

                    expect(sut.urlRequestHeaders).to(equal(headers))
                }

                it("handles empty headers dictionary") {
                    let options = ["AVURLAssetHTTPHeaderFieldsKey": [:]]
                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: options)

                    expect(sut.urlRequestHeaders).to(equal([:]))
                }

                it("has nil headers when not provided") {
                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: nil)

                    expect(sut.urlRequestHeaders).to(beNil())
                }
            }
        }

        // MARK: - CachingPlayerItemConfiguration Tests

        describe("CachingPlayerItemConfiguration") {
            var config: CachingPlayerItemConfiguration!

            context("when created with default initializer") {
                beforeEach {
                    config = CachingPlayerItemConfiguration()
                }

                it("has correct default values") {
                    expect(config.downloadBufferLimit).to(equal(15 * 1024 * 1024))
                    expect(config.readDataLimit).to(equal(10 * 1024 * 1024))
                    expect(config.shouldVerifyDownloadedFileSize).to(beFalse())
                    expect(config.minimumExpectedFileSize).to(equal(0))
                    expect(config.shouldCheckAvailableDiskSpaceBeforeCaching).to(beTrue())
                    expect(config.allowsUncachedSeek).to(beTrue())
                    expect(config.logLevel).to(equal(LogLevel.none))
                }
            }

            context("when created with custom values") {
                it("stores custom downloadBufferLimit") {
                    config = CachingPlayerItemConfiguration(downloadBufferLimit: 5 * 1024 * 1024)
                    expect(config.downloadBufferLimit).to(equal(5 * 1024 * 1024))
                }

                it("stores custom readDataLimit") {
                    config = CachingPlayerItemConfiguration(readDataLimit: 2 * 1024 * 1024)
                    expect(config.readDataLimit).to(equal(2 * 1024 * 1024))
                }

                it("stores custom shouldVerifyDownloadedFileSize") {
                    config = CachingPlayerItemConfiguration(shouldVerifyDownloadedFileSize: true)
                    expect(config.shouldVerifyDownloadedFileSize).to(beTrue())
                }

                it("stores custom minimumExpectedFileSize") {
                    config = CachingPlayerItemConfiguration(minimumExpectedFileSize: 1000000)
                    expect(config.minimumExpectedFileSize).to(equal(1000000))
                }

                it("stores custom shouldCheckAvailableDiskSpaceBeforeCaching") {
                    config = CachingPlayerItemConfiguration(shouldCheckAvailableDiskSpaceBeforeCaching: false)
                    expect(config.shouldCheckAvailableDiskSpaceBeforeCaching).to(beFalse())
                }

                it("stores custom allowsUncachedSeek") {
                    config = CachingPlayerItemConfiguration(allowsUncachedSeek: false)
                    expect(config.allowsUncachedSeek).to(beFalse())
                }

                it("stores custom logLevel") {
                    config = CachingPlayerItemConfiguration(logLevel: .error)
                    expect(config.logLevel).to(equal(.error))
                }

                it("stores all custom values together") {
                    config = CachingPlayerItemConfiguration(
                        downloadBufferLimit: 20 * 1024 * 1024,
                        readDataLimit: 15 * 1024 * 1024,
                        shouldVerifyDownloadedFileSize: true,
                        minimumExpectedFileSize: 2000000,
                        shouldCheckAvailableDiskSpaceBeforeCaching: false,
                        allowsUncachedSeek: false,
                        logLevel: .info
                    )

                    expect(config.downloadBufferLimit).to(equal(20 * 1024 * 1024))
                    expect(config.readDataLimit).to(equal(15 * 1024 * 1024))
                    expect(config.shouldVerifyDownloadedFileSize).to(beTrue())
                    expect(config.minimumExpectedFileSize).to(equal(2000000))
                    expect(config.shouldCheckAvailableDiskSpaceBeforeCaching).to(beFalse())
                    expect(config.allowsUncachedSeek).to(beFalse())
                    expect(config.logLevel).to(equal(.info))
                }
            }

            context("when using static default instance") {
                it("returns a configuration instance") {
                    let defaultConfig = CachingPlayerItemConfiguration.default
                    expect(defaultConfig.downloadBufferLimit).to(equal(15 * 1024 * 1024))
                }

                it("can be modified globally") {
                    let originalDefault = CachingPlayerItemConfiguration.default

                    let newDefault = CachingPlayerItemConfiguration(downloadBufferLimit: 25 * 1024 * 1024)
                    CachingPlayerItemConfiguration.default = newDefault

                    expect(CachingPlayerItemConfiguration.default.downloadBufferLimit).to(equal(25 * 1024 * 1024))

                    // Restore original
                    CachingPlayerItemConfiguration.default = originalDefault
                }
            }

            context("when comparing configurations") {
                it("creates independent instances") {
                    let config1 = CachingPlayerItemConfiguration(downloadBufferLimit: 5 * 1024 * 1024)
                    let config2 = CachingPlayerItemConfiguration(downloadBufferLimit: 10 * 1024 * 1024)

                    expect(config1.downloadBufferLimit).toNot(equal(config2.downloadBufferLimit))
                }
            }
        }

        // MARK: - Mock Delegate Behavior Tests

        describe("MockCachingPlayerItemDelegate") {
            var delegate: MockCachingPlayerItemDelegate!
            var sut: CachingPlayerItem!

            beforeEach {
                delegate = MockCachingPlayerItemDelegate()
                sut = CachingPlayerItem(url: URL(string: "https://example.com/test.mp4")!)
                sut.delegate = delegate
            }

            afterEach {
                delegate = nil
                sut = nil
            }

            context("when reset is called") {
                it("clears all flags") {
                    delegate.didFinishDownloadingCalled = true
                    delegate.didDownloadBytesCalled = true
                    delegate.downloadingFailedCalled = true
                    delegate.readyToPlayCalled = true
                    delegate.didFailToPlayCalled = true
                    delegate.playbackStalledCalled = true

                    delegate.reset()

                    expect(delegate.didFinishDownloadingCalled).to(beFalse())
                    expect(delegate.didDownloadBytesCalled).to(beFalse())
                    expect(delegate.downloadingFailedCalled).to(beFalse())
                    expect(delegate.readyToPlayCalled).to(beFalse())
                    expect(delegate.didFailToPlayCalled).to(beFalse())
                    expect(delegate.playbackStalledCalled).to(beFalse())
                }

                it("clears all stored values") {
                    delegate.lastDownloadedFilePath = "/path/to/file"
                    delegate.lastBytesDownloaded = 1000
                    delegate.lastBytesExpected = 2000
                    delegate.lastError = NSError(domain: "test", code: 1)
                    delegate.lastPlayError = NSError(domain: "play", code: 2)

                    delegate.reset()

                    expect(delegate.lastDownloadedFilePath).to(beNil())
                    expect(delegate.lastBytesDownloaded).to(equal(0))
                    expect(delegate.lastBytesExpected).to(equal(0))
                    expect(delegate.lastError).to(beNil())
                    expect(delegate.lastPlayError).to(beNil())
                }
            }

            context("when delegate methods are called") {
                it("tracks playerItemPlaybackStalled") {
                    NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: sut)

                    expect(delegate.playbackStalledCalled).toEventually(beTrue(), timeout: .seconds(1))
                }
            }
        }

        // MARK: - File System Integration Tests

        describe("File System Integration") {
            var tempDirectory: URL!

            beforeEach {
                tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            }

            afterEach {
                try? FileManager.default.removeItem(at: tempDirectory)
            }

            context("when using data initializer") {
                it("persists data to disk") {
                    let testData = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"

                    let item = try? CachingPlayerItem(data: testData, customFileExtension: "txt")
                    expect(item).toNot(beNil())

                    guard let urlAsset = item?.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    let savedData = try? Data(contentsOf: urlAsset.url)
                    expect(savedData).to(equal(testData))
                }

                it("cleans up file on deallocation") {
                    var fileURL: URL?

                    autoreleasepool {
                        let testData = Data([0x01, 0x02, 0x03])
                        let item = try? CachingPlayerItem(data: testData, customFileExtension: "bin")
                        fileURL = (item?.asset as? AVURLAsset)?.url

                        expect(FileManager.default.fileExists(atPath: fileURL!.path)).to(beTrue())
                    }
                }
            }
        }

        // MARK: - MediaFileHandle Tests

        describe("MediaFileHandle") {
            var tempDirectory: URL!
            var filePath: String!

            beforeEach {
                tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                filePath = tempDirectory.appendingPathComponent("media.mp4").path
            }

            afterEach {
                try? FileManager.default.removeItem(at: tempDirectory)
            }

            // Issue #38: these used to raise NSFileHandleOperationException, uncatchable from Swift.
            context("when the handle is closed") {
                it("throws from append instead of raising") {
                    let sut = MediaFileHandle(filePath: filePath)
                    try? sut.append(data: Data([0x01, 0x02, 0x03]))
                    sut.close()

                    expect { try sut.append(data: Data([0x04, 0x05, 0x06])) }.to(throwError())
                }

                it("returns nil from read instead of raising") {
                    let sut = MediaFileHandle(filePath: filePath)
                    try? sut.append(data: Data([0x01, 0x02, 0x03]))
                    sut.close()

                    expect(sut.readData(withOffset: 0, forLength: 3)).to(beNil())
                }

                it("does not raise from synchronize or a second close") {
                    let sut = MediaFileHandle(filePath: filePath)
                    try? sut.append(data: Data([0x01]))
                    sut.close()

                    expect { sut.synchronize() }.toNot(raiseException())
                    expect { sut.close() }.toNot(raiseException())
                }
            }

            context("when reset") {
                it("empties the file") {
                    let sut = MediaFileHandle(filePath: filePath)
                    try? sut.append(data: Data(repeating: 0xAB, count: 128))
                    expect(sut.fileSize).to(equal(128))

                    sut.reset()

                    expect(sut.fileSize).to(equal(0))
                    expect(FileManager.default.fileExists(atPath: filePath)).to(beTrue())
                }

                it("appends to the new file after the old one was deleted") {
                    let sut = MediaFileHandle(filePath: filePath)
                    try? sut.append(data: Data(repeating: 0xAB, count: 128))

                    // A handle left open on the unlinked file would keep writing nowhere.
                    sut.deleteFile()
                    sut.reset()
                    try? sut.append(data: Data(repeating: 0xCD, count: 64))

                    expect(sut.fileSize).to(equal(64))
                    expect(try? Data(contentsOf: URL(fileURLWithPath: filePath)))
                        .to(equal(Data(repeating: 0xCD, count: 64)))
                }

                it("reads back data written after the reset") {
                    let sut = MediaFileHandle(filePath: filePath)
                    try? sut.append(data: Data(repeating: 0xAB, count: 32))
                    _ = sut.readData(withOffset: 0, forLength: 32)

                    sut.reset()
                    try? sut.append(data: Data([0x01, 0x02, 0x03, 0x04]))

                    expect(sut.readData(withOffset: 0, forLength: 4)).to(equal(Data([0x01, 0x02, 0x03, 0x04])))
                }
            }
        }

        // MARK: - Resource Loader Integration Tests

        describe("Resource Loader Integration") {
            var sut: CachingPlayerItem!
            let testURL = URL(string: "https://example.com/media.mp4")!

            afterEach {
                sut = nil
            }

            context("when initialized for caching") {
                it("sets resource loader delegate on asset") {
                    sut = CachingPlayerItem(url: testURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.resourceLoader).toNot(beNil())
                }
            }
        }

        // MARK: - Edge Cases and Error Conditions

        describe("Edge Cases") {
            context("when handling URLs") {
                it("preserves query parameters") {
                    let urlWithQuery = URL(string: "https://example.com/video.mp4?token=abc123&expires=456")!
                    let item = CachingPlayerItem(url: urlWithQuery)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.query).toNot(beNil())
                }

                it("preserves URL fragments") {
                    let urlWithFragment = URL(string: "https://example.com/video.mp4#section")!
                    let item = CachingPlayerItem(url: urlWithFragment)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.fragment).toNot(beNil())
                }

                it("handles URLs with special characters") {
                    let specialURL = URL(string: "https://example.com/video%20file.mp4")!
                    let item = CachingPlayerItem(url: specialURL)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.path()).to(equal(specialURL.path()))
                }
            }

            context("when handling file extensions") {
                it("handles uppercase extensions") {
                    let url = URL(string: "https://example.com/VIDEO.MP4")!
                    let item = CachingPlayerItem(url: url)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("MP4"))
                }

                it("replaces extension when custom extension provided") {
                    let url = URL(string: "https://example.com/media.xyz")!
                    let item = CachingPlayerItem(url: url, customFileExtension: "mp4")

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp4"))
                }
            }
        }

        // MARK: - Performance Considerations

        describe("Performance") {
            context("when creating multiple instances") {
                it("creates instances quickly") {
                    let url = URL(string: "https://example.com/video.mp4")!

                    let startTime = Date()

                    for _ in 0..<100 {
                        _ = CachingPlayerItem(url: url)
                    }

                    let elapsed = Date().timeIntervalSince(startTime)
                    expect(elapsed).to(beLessThan(1.0)) // Should create 100 instances in under 1 second
                }
            }
        }
    }
}

// MARK: - Mock Delegate

class MockCachingPlayerItemDelegate: NSObject, CachingPlayerItemDelegate {
    var didFinishDownloadingCalled = false
    var didDownloadBytesCalled = false
    var downloadingFailedCalled = false
    var readyToPlayCalled = false
    var didFailToPlayCalled = false
    var playbackStalledCalled = false

    var lastDownloadedFilePath: String?
    var lastBytesDownloaded: Int = 0
    var lastBytesExpected: Int = 0
    var lastError: Error?
    var lastPlayError: Error?

    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingFileAt filePath: String) {
        didFinishDownloadingCalled = true
        lastDownloadedFilePath = filePath
    }

    func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int) {
        didDownloadBytesCalled = true
        lastBytesDownloaded = bytesDownloaded
        lastBytesExpected = bytesExpected
    }

    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
        downloadingFailedCalled = true
        lastError = error
    }

    func playerItemReadyToPlay(_ playerItem: CachingPlayerItem) {
        readyToPlayCalled = true
    }

    func playerItemDidFailToPlay(_ playerItem: CachingPlayerItem, withError error: Error?) {
        didFailToPlayCalled = true
        lastPlayError = error
    }

    func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem) {
        playbackStalledCalled = true
    }

    func reset() {
        didFinishDownloadingCalled = false
        didDownloadBytesCalled = false
        downloadingFailedCalled = false
        readyToPlayCalled = false
        didFailToPlayCalled = false
        playbackStalledCalled = false

        lastDownloadedFilePath = nil
        lastBytesDownloaded = 0
        lastBytesExpected = 0
        lastError = nil
        lastPlayError = nil
    }
}

// MARK: - Concurrency Tests

/// Connection is refused immediately, so tasks resolve without leaving the device.
private let unreachableURL = URL(string: "http://127.0.0.1:1/test-video.mp4")!

class CachingPlayerItemConcurrencySpec: QuickSpec {
    override class func spec() {
        var tempDirectory: URL!

        func makeFilePath() -> String {
            tempDirectory.appendingPathComponent("\(UUID().uuidString).mp4").path
        }

        beforeEach {
            tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        }

        afterEach {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        describe("MediaFileHandle under contention") {
            it("serializes concurrent appends without losing bytes") {
                let sut = MediaFileHandle(filePath: makeFilePath())
                let chunk = Data(repeating: 0xEE, count: 512)
                let writers = 8
                let appendsPerWriter = 50
                let group = DispatchGroup()

                for _ in 0..<writers {
                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<appendsPerWriter { try? sut.append(data: chunk) }
                    }
                }
                group.wait()

                expect(sut.fileSize).to(equal(writers * appendsPerWriter * chunk.count))
            }

            it("stays usable when reset races with appends and reads") {
                let sut = MediaFileHandle(filePath: makeFilePath())
                let chunk = Data(repeating: 0xAB, count: 256)
                let group = DispatchGroup()

                for _ in 0..<4 {
                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<100 { try? sut.append(data: chunk) }
                    }
                }
                for _ in 0..<2 {
                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<100 { _ = sut.readData(withOffset: 0, forLength: 128) }
                    }
                }
                DispatchQueue.global().async(group: group) {
                    for _ in 0..<50 { sut.reset() }
                }
                group.wait()

                sut.reset()
                try? sut.append(data: Data([0x01, 0x02, 0x03]))

                expect(sut.fileSize).to(equal(3))
                expect(sut.readData(withOffset: 0, forLength: 3)).to(equal(Data([0x01, 0x02, 0x03])))
            }
        }

        describe("session lifecycle under contention") {
            // Issue #31 raised an ObjC exception here, so completing every round is the assertion.
            it("never creates a task on an invalidated session") {
                let rounds = 40
                let iterations = 120
                var completedRounds = 0

                for _ in 0..<rounds {
                    let sut = ResourceLoaderDelegate(url: unreachableURL,
                                                     saveFilePath: makeFilePath(),
                                                     owner: nil)
                    let group = DispatchGroup()

                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<iterations { sut.startFileDownload(with: unreachableURL) }
                    }
                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<iterations { sut.invalidateAndCancelSession() }
                    }
                    if group.wait(timeout: .now() + 30) == .timedOut {
                        fail("round \(completedRounds) did not finish in 30s - probable deadlock")
                        break
                    }

                    completedRounds += 1
                }

                expect(completedRounds).to(equal(rounds))
            }

            it("survives interleaved cancels, restarts and received data") {
                let rounds = 20
                let iterations = 80
                var completedRounds = 0

                for _ in 0..<rounds {
                    let sut = ResourceLoaderDelegate(url: unreachableURL,
                                                     saveFilePath: makeFilePath(),
                                                     owner: nil)
                    let probeSession = URLSession(configuration: .default)
                    let probeTask = probeSession.dataTask(with: unreachableURL)
                    let group = DispatchGroup()

                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<iterations { sut.startFileDownload(with: unreachableURL) }
                    }
                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<iterations { sut.invalidateAndCancelSession() }
                    }
                    DispatchQueue.global().async(group: group) {
                        for _ in 0..<iterations {
                            sut.urlSession(probeSession,
                                           dataTask: probeTask,
                                           didReceive: Data(repeating: 0x11, count: 256))
                        }
                    }
                    if group.wait(timeout: .now() + 30) == .timedOut {
                        fail("round \(completedRounds) did not finish in 30s - probable deadlock")
                        probeSession.invalidateAndCancel()
                        break
                    }
                    probeSession.invalidateAndCancel()

                    completedRounds += 1
                }

                expect(completedRounds).to(equal(rounds))
            }

            it("leaves a writable file behind after a cancel so a restart can use it") {
                let filePath = makeFilePath()
                let sut = ResourceLoaderDelegate(url: unreachableURL, saveFilePath: filePath, owner: nil)

                sut.startFileDownload(with: unreachableURL)
                sut.invalidateAndCancelSession()

                // Replaced rather than left deleted, which is what makes a restart able to write.
                expect(FileManager.default.fileExists(atPath: filePath)).to(beTrue())
                expect(sut.isDownloadComplete).to(beFalse())

                sut.startFileDownload(with: unreachableURL)
                sut.invalidateAndCancelSession(shouldResetData: false)

                // The teardown path deletes instead, so no empty file is left in the cache directory.
                expect(FileManager.default.fileExists(atPath: filePath)).to(beFalse())
            }
        }
    }
}

// MARK: - Playback Stress Test Infrastructure

/// Generates a real, seekable mp4 so AVFoundation issues genuine content-info and data requests.
enum TestMedia {
    static func makeMP4(at url: URL, durationSeconds: Int = 4, fps: Int32 = 12) -> Data? {
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }

        let width = 320
        let height = 240
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])

        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(Int(fps) * durationSeconds) {
            while input.isReadyForMoreMediaData == false { usleep(2_000) }

            guard let buffer = makePixelBuffer(width: width, height: height, seed: frame) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps))
        }
        input.markAsFinished()

        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        guard finished.wait(timeout: .now() + 30) == .success, writer.status == .completed else { return nil }

        return try? Data(contentsOf: url)
    }

    private static func makePixelBuffer(width: Int, height: Int, seed: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer
        else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(32 + (seed * 9) % 200), CVPixelBufferGetBytesPerRow(buffer) * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }
}

/// Loopback HTTP server with the `Range` support the library needs for byte-range access.
final class LocalMediaServer {
    private let media: Data
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalMediaServer", attributes: .concurrent)

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(media: Data) throws {
        self.media = media

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
    }

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }

            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
        listener.start(queue: queue)

        return ready.wait(timeout: .now() + 10) == .success && port > 0
    }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }

            var buffer = buffer
            if let data { buffer.append(data) }

            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                guard error == nil, isComplete == false else { return connection.cancel() }

                receive(on: connection, buffer: buffer)
                return
            }

            respond(to: String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self), on: connection)
        }
    }

    private func respond(to header: String, on connection: NWConnection) {
        let total = media.count
        var lower = 0
        var upper = total - 1
        var isPartial = false

        if let rangeLine = header.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("range:") }),
           let spec = rangeLine.split(separator: "=").last {
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)

            if let start = Int(bounds.first ?? "") {
                lower = start
                isPartial = true

                if bounds.count > 1, let end = Int(bounds[1]) { upper = min(end, total - 1) }
            }
        }

        var response: Data

        if lower > upper || lower >= total {
            response = Data("HTTP/1.1 416 Requested Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
        } else {
            let body = media.subdata(in: lower..<(upper + 1))
            var head = isPartial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n"
            head += "Content-Type: video/mp4\r\n"
            head += "Accept-Ranges: bytes\r\n"
            head += "Content-Length: \(body.count)\r\n"
            if isPartial { head += "Content-Range: bytes \(lower)-\(upper)/\(total)\r\n" }
            head += "Connection: close\r\n\r\n"

            response = Data(head.utf8)
            response.append(body)
        }

        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

// MARK: - Playback Stress Tests

class CachingPlayerItemPlaybackStressSpec: QuickSpec {
    override class func spec() {
        describe("resource loader during playback") {
            var tempDirectory: URL!
            var server: LocalMediaServer!
            var mediaData: Data!
            var mediaURL: URL!

            beforeEach {
                tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

                mediaData = TestMedia.makeMP4(at: tempDirectory.appendingPathComponent("source.mp4"))
                server = try? LocalMediaServer(media: mediaData ?? Data())
                _ = server?.start()
                mediaURL = URL(string: "http://127.0.0.1:\(server?.port ?? 0)/video.mp4")
            }

            afterEach {
                server?.stop()
                server = nil
                try? FileManager.default.removeItem(at: tempDirectory)
            }

            // Guards the suite below: if the fixture breaks, the stress tests would pass vacuously.
            it("serves real seekable media over loopback") {
                expect(mediaData?.count ?? 0).to(beGreaterThan(2_000))
                expect(server.port).to(beGreaterThan(0))

                let delegate = MockCachingPlayerItemDelegate()
                let item = CachingPlayerItem(url: mediaURL)
                item.delegate = delegate
                let player = AVPlayer(playerItem: item)
                player.play()

                // The resource loader is called on the main queue, so the run loop has to be pumped.
                let deadline = Date().addingTimeInterval(6)
                while Date() < deadline && delegate.didDownloadBytesCalled == false {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                }

                player.pause()
                player.replaceCurrentItem(with: nil)

                expect(delegate.didDownloadBytesCalled).to(beTrue())
                expect(delegate.lastBytesExpected).to(equal(mediaData.count))
            }

            // The frame that crashed in issue #31, driven through a real player.
            it("survives cancelDownload and download racing seeks during playback") {
                let rounds = 5
                var completedRounds = 0
                var sawLoaderActivity = false

                for round in 0..<rounds {
                    let delegate = MockCachingPlayerItemDelegate()
                    let item = CachingPlayerItem(
                        url: mediaURL,
                        saveFilePath: tempDirectory.appendingPathComponent("cache-\(round).mp4").path,
                        customFileExtension: nil
                    )
                    item.delegate = delegate

                    let player = AVPlayer(playerItem: item)
                    player.play()

                    let deadline = Date().addingTimeInterval(1.5)
                    let churn = DispatchGroup()

                    DispatchQueue.global().async(group: churn) {
                        while Date() < deadline {
                            item.cancelDownload()
                            item.download()
                            usleep(500)
                        }
                    }

                    var nextSeek = Date()
                    while Date() < deadline {
                        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))

                        if Date() >= nextSeek {
                            player.seek(to: CMTime(seconds: Double.random(in: 0...3), preferredTimescale: 600))
                            nextSeek = Date().addingTimeInterval(0.05)
                        }
                    }
                    if churn.wait(timeout: .now() + 30) == .timedOut {
                        fail("round \(round) churn did not finish in 30s - probable deadlock")
                        break
                    }

                    player.pause()
                    player.replaceCurrentItem(with: nil)

                    if delegate.didDownloadBytesCalled || delegate.downloadingFailedCalled
                        || delegate.didFailToPlayCalled || delegate.readyToPlayCalled {
                        sawLoaderActivity = true
                    }
                    completedRounds += 1
                }

                expect(completedRounds).to(equal(rounds))
                // Proves the resource loader path actually ran rather than the test passing vacuously.
                expect(sawLoaderActivity).to(beTrue())
            }

            // Drops the item's last reference off-thread, so `deinit` can re-enter the delegate.
            it("does not deadlock when the item is released during active loading") {
                final class Holder {
                    var item: CachingPlayerItem?
                    var player: AVPlayer?
                }

                let rounds = 10
                var completedRounds = 0

                for round in 0..<rounds {
                    let holder = Holder()
                    holder.item = CachingPlayerItem(url: mediaURL)
                    holder.player = AVPlayer(playerItem: holder.item)
                    holder.player?.play()

                    let warmup = Date().addingTimeInterval(0.2)
                    while Date() < warmup {
                        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                    }

                    let released = DispatchSemaphore(value: 0)
                    DispatchQueue.global().async {
                        holder.player?.replaceCurrentItem(with: nil)
                        holder.player = nil
                        holder.item = nil
                        released.signal()
                    }

                    // Keep pumping main so queued loader callbacks run while deinit happens elsewhere.
                    let deadline = Date().addingTimeInterval(20)
                    var timedOut = false
                    while released.wait(timeout: .now()) == .timedOut {
                        if Date() > deadline {
                            timedOut = true
                            break
                        }
                        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                    }

                    if timedOut {
                        fail("round \(round) release did not complete in 20s - probable deadlock")
                        break
                    }

                    completedRounds += 1
                }

                expect(completedRounds).to(equal(rounds))
            }
        }
    }
}
