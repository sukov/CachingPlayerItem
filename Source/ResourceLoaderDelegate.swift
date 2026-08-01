//
//  ResourceLoaderDelegate.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation
import AVFoundation
import UIKit

/// Responsible for downloading media data and providing the requested data parts.
final class ResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    typealias PendingRequestId = Int

    private let bufferLock = NSLock()
    private let sessionLock = NSLock()

    private var bufferData = Data()
    private var bufferedByteCount: Int {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        return bufferData.count
    }
    private var configuration: CachingPlayerItemConfiguration { owner?.configuration ?? .default }

    private lazy var fileHandle = MediaFileHandle(filePath: saveFilePath)

    private var session: URLSession?
    private var isSessionInvalidated = false
    private let operationQueue = {
        let queue = OperationQueue()
        queue.name = "CachingPlayerItemOperationQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var pendingContentInfoRequest: PendingContentInfoRequest? {
        didSet { oldValue?.cancelTask() }
    }
    private var contentInfoResponseValue: URLResponse?
    private var contentInfoResponse: URLResponse? {
        get {
            sessionLock.lock()
            defer { sessionLock.unlock() }

            return contentInfoResponseValue
        }

        set {
            sessionLock.lock()
            defer { sessionLock.unlock() }

            contentInfoResponseValue = newValue
        }
    }
    private var pendingDataRequests: [PendingRequestId: PendingDataRequest] = [:]
    private var fullMediaFileDownloadTask: URLSessionDataTask?
    private var fullMediaFileDownloadTaskId: Int? {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        return fullMediaFileDownloadTask?.taskIdentifier
    }
    private var isDownloadCompleteValue = false
    var isDownloadComplete: Bool {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        return isDownloadCompleteValue
    }

    private let url: URL
    private let saveFilePath: String
    private weak var owner: CachingPlayerItem?

    // MARK: Init

    init(url: URL, saveFilePath: String, owner: CachingPlayerItem?) {
        self.url = url
        self.saveFilePath = saveFilePath
        self.owner = owner
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        // Strong reference kept, owner's deinit re-locks (deadlocks) sessionLock on this thread.
        let owner = self.owner

        startFileDownload(with: url)

        sessionLock.lock()
        defer { sessionLock.unlock() }

        guard let session else { return false }

        if let _ = loadingRequest.contentInformationRequest {
            let request = PendingContentInfoRequest(url: url, session: session, loadingRequest: loadingRequest, customHeaders: owner?.urlRequestHeaders)
            addOperationOnQueue { [weak self] in self?.pendingContentInfoRequest = request }
            request.startTask()
            return true
        } else if let _ = loadingRequest.dataRequest {
            let request = PendingDataRequest(url: url, session: session, loadingRequest: loadingRequest, customHeaders: owner?.urlRequestHeaders)
            request.delegate = self
            request.startTask()
            addOperationOnQueue { [weak self] in self?.pendingDataRequests[request.id] = request }
            return true
        } else {
            return false
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }
            guard let key = pendingDataRequests.first(where: { $1.loadingRequest == loadingRequest })?.key else { return }

            pendingDataRequests[key]?.cancelTask()
            pendingDataRequests.removeValue(forKey: key)
        }
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }

            pendingDataRequests[dataTask.taskIdentifier]?.respond(withRemoteData: data)
        }

        guard fullMediaFileDownloadTaskId == dataTask.taskIdentifier else { return }

        appendDataToBuffer(data)
        writeBufferDataToFileIfNeeded()

        guard let response = contentInfoResponse ?? dataTask.response else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, let owner = self.owner else { return }

            owner.delegate?.playerItem?(owner,
                                        didDownloadBytesSoFar: self.fileHandle.fileSize + self.bufferedByteCount,
                                        outOf: Int(response.processedInfoData.expectedContentLength))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }

            let taskId = task.taskIdentifier
            
            if let error {
                guard (error as? URLError)?.code != .cancelled else { return }

                if pendingContentInfoRequest?.id == taskId {
                    finishLoadingPendingRequest(withId: taskId, error: error)
                    downloadFailed(with: error)
                } else if fullMediaFileDownloadTaskId == taskId {
                    downloadFailed(with: error)
                }  else {
                    finishLoadingPendingRequest(withId: taskId, error: error)
                }

                return
            }

            if let response = task.response, pendingContentInfoRequest?.id == taskId {
                let insufficientDiskSpaceError = checkAvailableDiskSpaceIfNeeded(response: response)
                guard insufficientDiskSpaceError == nil else {
                    downloadFailed(with: insufficientDiskSpaceError!)
                    return
                }

                pendingContentInfoRequest?.fillInContentInformationRequest(with: response)
                finishLoadingPendingRequest(withId: taskId)
                contentInfoResponse = response
            } else {
                finishLoadingPendingRequest(withId: taskId)
            }

            guard fullMediaFileDownloadTaskId == taskId else { return }

            if bufferedByteCount > 0 {
                writeBufferDataToFileIfNeeded(forced: true)
            }

            let error = verify(response: contentInfoResponse ?? task.response)

            guard error == nil else {
                downloadFailed(with: error!)
                return
            }

            downloadComplete()
        }
    }

    // MARK: Internal methods

    func startFileDownload(with url: URL) {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        guard session == nil && isSessionInvalidated == false else { return }

        createURLSession()

        var urlRequest = URLRequest(url: url)
        owner?.urlRequestHeaders?.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }

        fullMediaFileDownloadTask = session?.dataTask(with: urlRequest)
        fullMediaFileDownloadTask?.resume()
    }

    func invalidateAndCancelSession(shouldResetData: Bool = true) {
        sessionLock.lock()
        session?.invalidateAndCancel()
        session = nil
        isSessionInvalidated = true
        sessionLock.unlock()

        operationQueue.cancelAllOperations()

        if shouldResetData {
            bufferLock.lock()
            bufferData = Data()
            bufferLock.unlock()

            addOperationOnQueue { [weak self] in
                guard let self else { return }

                pendingContentInfoRequest = nil
                pendingDataRequests.removeAll()
            }
        }

        // We need to only remove the file if it hasn't been fully downloaded
        guard isDownloadComplete == false else { return }

        fileHandle.deleteFile()
    }

    // MARK: Private methods

    private func createURLSession() {
        guard session == nil else {
            assertionFailure("Session already created.")
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private func finishLoadingPendingRequest(withId id: PendingRequestId, error: Error? = nil) {
        if pendingContentInfoRequest?.id == id {
            pendingContentInfoRequest?.finishLoading(with: error)
            pendingContentInfoRequest = nil
        } else if pendingDataRequests[id] != nil {
            pendingDataRequests[id]?.finishLoading(with: error)
            pendingDataRequests.removeValue(forKey: id)
        }
    }

    private func appendDataToBuffer(_ data: Data) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        bufferData.append(data)
    }

    private func writeBufferDataToFileIfNeeded(forced: Bool = false) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        guard bufferData.count >= configuration.downloadBufferLimit || forced else { return }

        fileHandle.append(data: bufferData)
        bufferData = Data()
    }

    private func downloadComplete() {
        sessionLock.lock()
        isDownloadCompleteValue = true
        sessionLock.unlock()

        DispatchQueue.main.async {
            self.owner?.delegate?.playerItem?(self.owner!, didFinishDownloadingFileAt: self.saveFilePath)
        }
    }

    private func verify(response: URLResponse?) -> NSError? {
        guard let response = response as? HTTPURLResponse else { return nil }

        let shouldVerifyDownloadedFileSize = configuration.shouldVerifyDownloadedFileSize
        let minimumExpectedFileSize = configuration.minimumExpectedFileSize
        var error: NSError?

        if response.statusCode >= 400 {
            error = NSError(domain: "Failed downloading asset. Reason: response status code \(response.statusCode).", code: response.statusCode, userInfo: nil)
        } else if shouldVerifyDownloadedFileSize && response.processedInfoData.expectedContentLength != -1 && response.processedInfoData.expectedContentLength != fileHandle.fileSize {
            error = NSError(domain: "Failed downloading asset. Reason: wrong file size, expected: \(response.expectedContentLength), actual: \(fileHandle.fileSize).", code: response.statusCode, userInfo: nil)
        } else if minimumExpectedFileSize > 0 && minimumExpectedFileSize > fileHandle.fileSize {
            error = NSError(domain: "Failed downloading asset. Reason: file size \(fileHandle.fileSize) is smaller than minimumExpectedFileSize", code: response.statusCode, userInfo: nil)
        }

        return error
    }

    private func checkAvailableDiskSpaceIfNeeded(response: URLResponse) -> NSError? {
        guard
            configuration.shouldCheckAvailableDiskSpaceBeforeCaching,
            let response = response as? HTTPURLResponse,
            let freeDiskSpace = fileHandle.freeDiskSpace
        else { return nil }

        if freeDiskSpace < response.processedInfoData.expectedContentLength {
            return NSError(domain: "Failed downloading asset. Reason: insufficient disk space available.", code: NSFileWriteOutOfSpaceError, userInfo: nil)
        }

        return nil
    }

    private func downloadFailed(with error: Error) {
        sessionLock.lock()
        isSessionInvalidated = true
        sessionLock.unlock()

        invalidateAndCancelSession()

        DispatchQueue.main.async {
            self.owner?.delegate?.playerItem?(self.owner!, downloadingFailedWith: error)
        }
    }

    private func addOperationOnQueue(_ block: @escaping () -> Void) {
        let blockOperation = BlockOperation()
        blockOperation.addExecutionBlock({ [unowned blockOperation] in
            guard blockOperation.isCancelled == false else { return }

            block()
        })
        operationQueue.addOperation(blockOperation)
    }

    @objc private func handleAppWillTerminate() {
        invalidateAndCancelSession(shouldResetData: false)
    }
}

// MARK: PendingDataRequestDelegate

extension ResourceLoaderDelegate: PendingDataRequestDelegate {
    func pendingDataRequest(_ request: PendingDataRequest, hasSufficientCachedDataFor offset: Int, with length: Int) -> Bool {
        if configuration.allowsUncachedSeek {
            // Request remote data temporarily if the requested data is not yet cached
            return fileHandle.fileSize >= length + offset
        } else {
            // Always request cached data
            return true
        }
    }

    func pendingDataRequest(_ request: PendingDataRequest,
                            requestCachedDataFor offset: Int,
                            with length: Int,
                            completion: @escaping ((_ continueRequesting: Bool) -> Void)) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }

            let bytesCached = fileHandle.fileSize
            // Data length to be loaded into memory with maximum size of readDataLimit.
            let bytesToRespond = min(bytesCached - offset, length, configuration.readDataLimit)
            // Read data from disk and pass it to the dataRequest
            guard let data = fileHandle.readData(withOffset: offset, forLength: bytesToRespond) else {
                finishLoadingPendingRequest(withId: request.id)
                completion(false)
                return
            }

            request.respond(withCachedData: data)

            if data.count >= length {
                finishLoadingPendingRequest(withId: request.id)
                completion(false)
            } else {
                completion(true)
            }
        }
    }
}
