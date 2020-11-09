//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0.

import AwsCHttp
import AwsCIo
import Foundation

public class HttpClientConnection {
    private let allocator: Allocator
    let rawValue: UnsafeMutablePointer<aws_http_connection>
    let manager: HttpClientConnectionManager

    init(manager: HttpClientConnectionManager,
         connection: UnsafeMutablePointer<aws_http_connection>,
         allocator: Allocator = defaultAllocator) {
        self.manager = manager
        self.allocator = allocator
        self.rawValue = connection
    }

    public var isOpen: Bool {
        return aws_http_connection_is_open(rawValue)
    }

    /// Close the http connection
    public func close() {
        manager.releaseConnection(connection: self)
    }

    /// Creates a new http stream from the `HttpRequestOptions` given.
    /// - Parameter requestOptions: An `HttpRequestOptions` struct containing callbacks on
    /// the different events from the stream
    /// - Returns: An `HttpStream` containing the `HttpClientConnection`
    public func makeRequest(requestOptions: HttpRequestOptions) -> HttpStream {
        var options = aws_http_make_request_options()
        options.self_size = MemoryLayout<aws_http_make_request_options>.size
        options.request = requestOptions.request.rawValue
        options.on_response_body = {_, data, userData -> Int32 in

            guard let userData = userData else {
                return -1
            }
            let httpStreamCbData: HttpStreamCallbackData = Unmanaged.fromOpaque(userData).takeUnretainedValue()
            guard let bufPtr = data!.pointee.ptr else {
                return -1
            }
            guard let bufLen = data?.pointee.len else {
                return -1
            }

            let callbackBytes = Data(bytesNoCopy: bufPtr, count: bufLen, deallocator: .none)
            httpStreamCbData.requestOptions.onIncomingBody!(httpStreamCbData.stream!, callbackBytes)

            return 0
        }
        options.on_response_headers = {_, headerBlock, headerArray, headersCount, userData -> Int32 in

            guard let userData = userData else {
                return -1
            }
            let httpStreamCbData: HttpStreamCallbackData = Unmanaged.fromOpaque(userData).takeUnretainedValue()

            var headers = [HttpHeader]()
            for cHeader in UnsafeBufferPointer(start: headerArray, count: headersCount) {
                if let name = cHeader.name.toString(),
                   let value = cHeader.value.toString() {
                    let swiftHeader = HttpHeader(name: name, value: value)
                    headers.append(swiftHeader)
                }

            }
            let headersStruct = HttpHeaders(fromArray: headers)
            httpStreamCbData.requestOptions.onIncomingHeaders(httpStreamCbData.stream!,
                                                              HttpHeaderBlock(rawValue: headerBlock),
                                                              headersStruct)
            return 0
        }
        options.on_response_header_block_done = {_, headerBlock, userData -> Int32 in

            guard let userData = userData else {
                return -1
            }
            let httpStreamCbData: HttpStreamCallbackData = Unmanaged.fromOpaque(userData).takeUnretainedValue()
            httpStreamCbData.requestOptions.onIncomingHeadersBlockDone(httpStreamCbData.stream!,
                                                                       HttpHeaderBlock(rawValue: headerBlock))
            return 0
        }
        options.on_complete = {_, errorCode, userData in

            guard let userData = userData else {
                return
            }
            let httpStreamCbData: HttpStreamCallbackData = Unmanaged.fromOpaque(userData).takeUnretainedValue()
            let error = AWSError(errorCode: errorCode)

            httpStreamCbData.requestOptions.onStreamComplete!(httpStreamCbData.stream!, CRTError.crtError(error))
        }

        let cbData = HttpStreamCallbackData(requestOptions: requestOptions)
        options.user_data = Unmanaged.passRetained(cbData).toOpaque()

        let stream = HttpStream(httpConnection: self)
        cbData.stream = stream
        stream.httpStream = aws_http_connection_make_request(rawValue, &options)

        return stream
    }

    deinit {
        aws_http_connection_release(rawValue)
    }
}
