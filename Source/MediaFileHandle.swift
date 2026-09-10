//
//  MediaFileHandle.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation

/// File handle for local file operations.
final class MediaFileHandle {
    private let filePath: String
    private lazy var readHandle = FileHandle(forReadingAtPath: filePath)
    private lazy var writeHandle = FileHandle(forWritingAtPath: filePath)

    private let lock = NSLock()

    // MARK: Init

    init(filePath: String) {
        self.filePath = filePath

        if !FileManager.default.fileExists(atPath: filePath) {
            FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil)
        } else {
            AppLogger.warning("File already exists at \(filePath). A non empty file can cause unexpected behavior.")
        }
    }

    deinit {
        guard FileManager.default.fileExists(atPath: filePath) else { return }

        close()
    }
}

// MARK: Internal methods

extension MediaFileHandle {
    var freeDiskSpace: Int64? {
        let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory() as String)
        let freeSpace = (systemAttributes?[FileAttributeKey.systemFreeSize] as? NSNumber)?.int64Value
        return freeSpace
    }

    var attributes: [FileAttributeKey : Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: filePath)
        } catch let error as NSError {
            AppLogger.error("Failed fetching attributes for \(filePath) with error: \(error)")
        }
        return nil
    }

    var fileSize: Int {
        return attributes?[.size] as? Int ?? 0
    }

    func readData(withOffset offset: Int, forLength length: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard let readHandle else { return nil }

        do {
            try readHandle.seek(toOffset: UInt64(offset))
            return try readHandle.read(upToCount: length)
        } catch {
            AppLogger.error("Failed reading \(length) bytes at offset \(offset) from \(filePath) with error: \(error)")
            return nil
        }
    }

    func append(data: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let writeHandle else { return }

        try writeHandle.seekToEnd()
        try writeHandle.write(contentsOf: data)
    }

    func synchronize() {
        lock.lock()
        defer { lock.unlock() }

        try? writeHandle?.synchronize()
    }

    func close() {
        try? readHandle?.close()
        try? writeHandle?.close()
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        close()

        if FileManager.default.fileExists(atPath: filePath) {
            deleteFile()
        }

        FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil)

        readHandle = FileHandle(forReadingAtPath: filePath)
        writeHandle = FileHandle(forWritingAtPath: filePath)
    }

    func deleteFile() {
        do {
            try FileManager.default.removeItem(atPath: filePath)
        } catch let error {
            AppLogger.error("File deletion failed at \(filePath) with error: \(error)")
        }
    }
}
