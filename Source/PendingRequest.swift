//
//  PendingRequest.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation
import AVFoundation

/// Abstract class with properties required for processing `AVAssetResourceLoadingRequest`.
class PendingRequest {
    /// URLSession task identifier.
    private(set) var id = -1
    private let url: URL
    private let customHeaders: [String: String]?
    private var task: URLSessionTask?
    private var didCancelTask = false
    fileprivate unowned var session: URLSession
    let loadingRequest: AVAssetResourceLoadingRequest
    var isCancelled: Bool { loadingRequest.isCancelled || didCancelTask }

    init(url: URL, session: URLSession, loadingRequest: AVAssetResourceLoadingRequest, customHeaders: [String: String]?) {
        self.url = url
        self.session = session
        self.loadingRequest = loadingRequest
        self.customHeaders = customHeaders
    }

    /// Creates an URLRequest with the required headers for bytes range and customHeaders set.
    private func makeURLRequest() -> URLRequest {
        var request = URLRequest(url: url)

        if let dataRequest = loadingRequest.dataRequest {
            let lowerBound = Int(dataRequest.requestedOffset)
            let upperBound = lowerBound + Int(dataRequest.requestedLength) - 1
            let rangeHeader = "bytes=\(lowerBound)-\(upperBound)"
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        if let headers = customHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }

    fileprivate func makeSessionTask(with request: URLRequest) -> URLSessionTask {
        fatalError("Subclasses need to implement the `makeSessionTask()` method.")
    }

    /// Creates the session task with `makeSessionTask` from subclass. `id` gets assigned with the task id when invoking this method.
    func startTask() {
        let request = makeURLRequest()
        let task = makeSessionTask(with: request)
        id = task.taskIdentifier
        self.task = task
        task.resume()
    }

    func cancelTask() {
        task?.cancel()

        if !loadingRequest.isCancelled && !loadingRequest.isFinished {
            finishLoading()
        }

        didCancelTask = true
    }

    func finishLoading(with error: Error? = nil) {
        if let error {
            loadingRequest.finishLoading(with: error)
        } else {
            loadingRequest.finishLoading()
        }
    }
}

// MARK: PendingContentInfoRequest

/// Wrapper for handling `AVAssetResourceLoadingContentInformationRequest`.
class PendingContentInfoRequest: PendingRequest {
    private var contentInformationRequest: AVAssetResourceLoadingContentInformationRequest {
        loadingRequest.contentInformationRequest!
    }

    override func makeSessionTask(with request: URLRequest) -> URLSessionTask {
        session.downloadTask(with: request)
    }

    func fillInContentInformationRequest(with response: URLResponse) {
        contentInformationRequest.contentType = response.processedInfoData.mimeType
        contentInformationRequest.contentLength = response.processedInfoData.expectedContentLength
        contentInformationRequest.isByteRangeAccessSupported = response.processedInfoData.isByteRangeAccessSupported
    }
}

// MARK: PendingDataRequest

/// Cached data request delegate.
protocol PendingDataRequestDelegate: AnyObject {
    /// Tells the `PendingDataRequest` if there is enough cached data.
    func pendingDataRequest(_ request: PendingDataRequest, hasSufficientCachedDataFor offset: Int, with length: Int) -> Bool
    /// Requests cached data. The returned `offset` and `length` are increased/reduced based on the data passed in `respond(withCachedData:)`.
    func pendingDataRequest(_ request: PendingDataRequest,
                            requestCachedDataFor offset: Int,
                            with length: Int,
                            completion: @escaping ((_ continueRequesting: Bool) -> Void))
}

/// Wrapper for handling  `AVAssetResourceLoadingDataRequest`.
class PendingDataRequest: PendingRequest {
    private var dataRequest: AVAssetResourceLoadingDataRequest { loadingRequest.dataRequest! }
    private lazy var requestedLength = dataRequest.requestedLength
    private lazy var fileDataOffset = Int(dataRequest.requestedOffset)
    weak var delegate: PendingDataRequestDelegate?

    override func makeSessionTask(with request: URLRequest) -> URLSessionTask {
        session.dataTask(with: request)
    }

    override func startTask() {
        if delegate?.pendingDataRequest(self, hasSufficientCachedDataFor: fileDataOffset, with: requestedLength) == true {
            // Cached data
            requestCachedData()
        } else {
            // Remote data
            super.startTask()
        }
    }

    func respond(withRemoteData data: Data) {
        dataRequest.respond(with: data)
    }

    func respond(withCachedData data: Data) {
        dataRequest.respond(with: data)
        fileDataOffset += data.count
        requestedLength -= data.count
    }

    /// Requests cached data recursively until `continueRequesting` is false.
    private func requestCachedData() {
        guard let delegate else { return }

        delegate.pendingDataRequest(
            self,
            requestCachedDataFor: fileDataOffset,
            with: requestedLength,
            completion: { [weak self] continueRequesting in
                if continueRequesting {
                    self?.requestCachedData()
                }
        })
    }
}
