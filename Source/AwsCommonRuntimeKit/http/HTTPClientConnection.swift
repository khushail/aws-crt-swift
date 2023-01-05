//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0.

import AwsCHttp
import AwsCIo
import Foundation

/// Represents one HTTP request/response exchange that can be used to
/// execute requests.
///
/// There are two implementations: HTTPClientConnection and HTTP2ClientConnection
public protocol HTTPExchange {
    var isOpen: Bool { get }
    var httpVersion: HTTPVersion { get }
    func close()
    func makeRequest(requestOptions: HTTPRequestOptions) throws -> HTTPStream
}

// swiftlint:disable force_try
public class HTTPClientConnection: HTTPExchange {
    private let allocator: Allocator
    let rawValue: UnsafeMutablePointer<aws_http_connection>
    /// This will keep the connection manager alive until connection is alive
    let manager: HTTPClientConnectionManager

    /// Called by HTTPClientConnectionManager
    init(manager: HTTPClientConnectionManager,
         connection: UnsafeMutablePointer<aws_http_connection>,
         allocator: Allocator = defaultAllocator) {
        self.manager = manager
        self.allocator = allocator
        self.rawValue = connection
    }

    public var isOpen: Bool {
        return aws_http_connection_is_open(rawValue)
    }

    public var httpVersion: HTTPVersion {
        HTTPVersion(rawValue: aws_http_connection_get_version(rawValue))
    }

    /// Close the http connection
    public func close() {
        aws_http_connection_close(rawValue)
    }

    /// Creates a new http stream from the `HTTPRequestOptions` given.
    /// - Parameter requestOptions: An `HTTPRequestOptions` struct containing callbacks on
    /// the different events from the stream
    /// - Returns: An `HTTPStream` containing the `HTTPClientConnection`
    public func makeRequest(requestOptions: HTTPRequestOptions) throws -> HTTPStream {
        let httpStreamCallbackCore = HTTPStreamCallbackCore(requestOptions: requestOptions)
        do {
            return try HTTPStream(httpConnection: self,
                                  options: httpStreamCallbackCore.getRetainedHttpMakeRequestOptions(),
                                  callbackData: httpStreamCallbackCore)
        } catch {
            httpStreamCallbackCore.release()
            throw error
        }
    }

    deinit {
        try! manager.releaseConnection(connection: self)
    }
}
