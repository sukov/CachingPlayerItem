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

    private let lock = NSLock()

    private var bufferData = Data()
    private let downloadBufferLimit = CachingPlayerItemConfiguration.downloadBufferLimit
    private let readDataLimit = CachingPlayerItemConfiguration.readDataLimit

    private lazy var fileHandle = MediaFileHandle(filePath: saveFilePath)

    private var session: URLSession?
    private let operationQueue = {
        let queue = OperationQueue()
        queue.name = "CachingPlayerItemOperationQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var pendingContentInfoRequest: PendingContentInfoRequest? {
        didSet { oldValue?.cancelTask() }
    }
    private var contentInfoResponse: URLResponse?
    private var pendingDataRequests: [PendingRequestId: PendingDataRequest] = [:]
    private var fullMediaFileDownloadTask: URLSessionDataTask?
    private var isDownloadComplete = false

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
        if session == nil {
            startFileDownload(with: url)
        }

        assert(session != nil, "Session must be set before proceeding.")
        guard let session else { return false }

        if let _ = loadingRequest.contentInformationRequest {
            pendingContentInfoRequest = PendingContentInfoRequest(url: url, session: session, loadingRequest: loadingRequest, customHeaders: owner?.urlRequestHeaders)
            pendingContentInfoRequest?.startTask()
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
            guard let key = pendingDataRequests.first(where: { $1.loadingRequest.request.url == loadingRequest.request.url })?.key else { return }

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

        if fullMediaFileDownloadTask?.taskIdentifier == dataTask.taskIdentifier {
            bufferData.append(data)
            writeBufferDataToFileIfNeeded()

            guard let response = contentInfoResponse ?? dataTask.response else { return }

            DispatchQueue.main.async {
                self.owner?.delegate?.playerItem?(self.owner!,
                                                  didDownloadBytesSoFar: self.fileHandle.fileSize + self.bufferData.count,
                                                  outOf: Int(response.processedInfoData.expectedContentLength))
            }
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
                } else if fullMediaFileDownloadTask?.taskIdentifier == taskId {
                    downloadFailed(with: error)
                }  else {
                    finishLoadingPendingRequest(withId: taskId, error: error)
                }

                return
            }

            if let response = task.response, pendingContentInfoRequest?.id == taskId {
                pendingContentInfoRequest?.fillInContentInformationRequest(with: response)
                finishLoadingPendingRequest(withId: taskId)
                contentInfoResponse = response
            } else {
                finishLoadingPendingRequest(withId: taskId)
            }

            guard fullMediaFileDownloadTask?.taskIdentifier == taskId else { return }

            if bufferData.count > 0 {
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
        guard session == nil else { return }

        createURLSession()

        var urlRequest = URLRequest(url: url)
        owner?.urlRequestHeaders?.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }

        fullMediaFileDownloadTask = session?.dataTask(with: urlRequest)
        fullMediaFileDownloadTask?.resume()
    }

    func invalidateAndCancelSession(shouldResetData: Bool = true) {
        session?.invalidateAndCancel()
        session = nil
        operationQueue.cancelAllOperations()

        if shouldResetData {
            bufferData = Data()
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

    private func writeBufferDataToFileIfNeeded(forced: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        guard 
            let availableSpace = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false).resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
            availableSpace > Int64(bufferData.count), 
            bufferData.count >= downloadBufferLimit || force 
        else {
             return
        }

        fileHandle.append(data: bufferData)
        bufferData = Data()
    }

    private func downloadComplete() {
        isDownloadComplete = true

        DispatchQueue.main.async {
            self.owner?.delegate?.playerItem?(self.owner!, didFinishDownloadingFileAt: self.saveFilePath)
        }
    }

    private func verify(response: URLResponse?) -> NSError? {
        guard let response = response as? HTTPURLResponse else { return nil }

        let shouldVerifyDownloadedFileSize = CachingPlayerItemConfiguration.shouldVerifyDownloadedFileSize
        let minimumExpectedFileSize = CachingPlayerItemConfiguration.minimumExpectedFileSize
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

    private func downloadFailed(with error: Error) {
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
        fileHandle.fileSize >= length + offset
    }

    func pendingDataRequest(_ request: PendingDataRequest,
                            requestCachedDataFor offset: Int,
                            with length: Int,
                            completion: @escaping ((_ continueRequesting: Bool) -> Void)) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }

            let bytesCached = fileHandle.fileSize
            // Data length to be loaded into memory with maximum size of readDataLimit.
            let bytesToRespond = min(bytesCached - offset, length, readDataLimit)
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
