//
//  URLResponseExtension.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation
import AVFoundation

extension URLResponse {
    struct ProcessedInfoData {
        let response: URLResponse

        var mimeType: String {
            if response.mimeType?.lowercased().contains("mp4") == true {
                return AVFileType.mp4.rawValue
            } else if response.mimeType?.lowercased().contains("mp3") == true {
                return AVFileType.mp3.rawValue
            }

            return AVFileType.mp4.rawValue
        }

        var expectedContentLength: Int64 {
            guard let response = response as? HTTPURLResponse else {
                return response.expectedContentLength
            }

            let contentRangeKeys: [String] = [
                "Content-Range",
                "content-range",
                "Content-range",
                "content-Range",
            ]

            var rangeString: String?

            for key in contentRangeKeys {
                if let value = response.allHeaderFields[key] as? String {
                    rangeString = value
                    break
                }
            }

            if let rangeString = rangeString,
               let bytesString = rangeString.split(separator: "/").map({String($0)}).last,
               let bytes = Int64(bytesString) {
                return bytes
            }

            return response.expectedContentLength
        }

        var isByteRangeAccessSupported: Bool {
            guard let response = response as? HTTPURLResponse else {
                return false
            }

            let rangeAccessKeys: [String] = [
                "Accept-Ranges",
                "accept-ranges",
                "Accept-ranges",
                "accept-Ranges",
            ]

            for key in rangeAccessKeys {
                if let value = response.allHeaderFields[key] as? String,
                   value == "bytes" {
                    return true
                }
            }

            return false
        }
    }

    var processedInfoData: ProcessedInfoData { .init(response: self) }
}
