//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0.
import AwsCHttp
import AwsCIo
import AwsCCommon
import Foundation

public struct HTTPRequestNew {

    public var method: String
    public var destination: URL
    public var headers: [HTTPHeader]
    public var body: IStreamable?
    public var allocator: Allocator = defaultAllocator

    public init(
            method: String,
            destination: URL,
            headers: [HTTPHeader],
            body: IStreamable? = nil,
            allocator: Allocator = defaultAllocator) {
        self.method = method
        self.destination = destination
        self.headers = headers
        self.body = body
        self.allocator = allocator
    }

    func withHTTPRequest<Result>(version: HTTPVersion, _ callback: (OpaquePointer) throws -> Result) throws -> Result {
        if version == .version_2 {
            return try withHTTP2Request { try callback($0) }
        }
        return try withHTTP1Request { try callback($0) }
    }

    func withHTTP2Request<Result>(_ callback: (OpaquePointer) throws -> Result) throws -> Result {
        guard let rawValue = aws_http2_message_new_request(allocator.rawValue) else {
            throw CommonRunTimeError.crtError(.makeFromLastError())
        }
        defer {
            aws_http_message_release(rawValue)
        }

        if let body = body {
            let iStreamCore = IStreamCore(iStreamable: body, allocator: allocator)
            aws_http_message_set_body_stream(rawValue, iStreamCore.rawValue)
        }

        //TODO: discuss , what about host header?
        var pseudoHeaders = [HTTPHeader]()
        pseudoHeaders.append(HTTPHeader(name: ":method", value: method))
        if !headers.contains(where: {$0.name == ":path"}) {
            pseudoHeaders.append(HTTPHeader(name: ":path", value: getPathAndQuery()))
        }
        if !headers.contains(where: {$0.name == ":scheme"}),
           let scheme = destination.scheme {
            pseudoHeaders.append(HTTPHeader(name: ":scheme", value: scheme))
        }
        if !headers.contains(where: {$0.name == ":authority"}),
           let host = destination.host {
            pseudoHeaders.append(HTTPHeader(name: ":authority", value: host))
        }

        try addHeaders(rawValue: rawValue, headers: pseudoHeaders + headers)
        return try callback(rawValue)
    }

    // Create a `CharacterSet` of the characters that need not be percent encoded in the
    // resulting URL.  This set consists of alphanumerics plus underscore, dash, tilde, and
    // period.  Any other character should be percent-encoded when used in a path segment.
    // Forward-slash is added as well because the segments have already been joined into a path.
    //
    // See, for URL-allowed characters:
    // https://www.rfc-editor.org/rfc/rfc3986#section-2.3
    private let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/_-.~"))
    //TODO: fix
    func getPathAndQuery() -> String {
        let encodedPath = destination.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? destination.path
        return "\(encodedPath)\(destination.query ?? "")"
    }

    func withHTTP1Request<Result>(_ callback: (OpaquePointer) throws -> Result) throws -> Result {
        guard let rawValue = aws_http_message_new_request(allocator.rawValue) else {
            throw CommonRunTimeError.crtError(.makeFromLastError())
        }
        defer {
            aws_http_message_release(rawValue)
        }

        method.withByteCursor { methodCursor in
            _ = aws_http_message_set_request_method(rawValue, methodCursor)
        }

        getPathAndQuery().withByteCursor { pathCursor in
            _ = aws_http_message_set_request_path(rawValue, pathCursor)
        }
        if let body = body {
            let iStreamCore = IStreamCore(iStreamable: body, allocator: allocator)
            aws_http_message_set_body_stream(rawValue, iStreamCore.rawValue)
        }

        try addHeaders(rawValue: rawValue, headers: headers)
        return try callback(rawValue)
    }

    func addHeaders(rawValue: OpaquePointer, headers: [HTTPHeader]) throws {
        try headers.forEach { header in
            guard !header.name.isEmpty else {
                return
            }

            guard (header.withCStruct { cHeader in
                aws_http_message_add_header(rawValue, cHeader)
            }) == AWS_OP_SUCCESS
            else {
                throw CommonRunTimeError.crtError(.makeFromLastError())
            }
        }
    }
}

public class HTTPRequest: HTTPRequestBase {

    public var method: String {
        get {
            var method = aws_byte_cursor()
            _ = aws_http_message_get_request_method(rawValue, &method)
            return method.toString()
        }
        set {
            newValue.withByteCursor { valueCursor in
                _ = aws_http_message_set_request_method(rawValue, valueCursor)
            }
        }
    }

    public var path: String {
        get {
            var path = aws_byte_cursor()
            _ = aws_http_message_get_request_path(rawValue, &path)
            return path.toString()
        }
        set {
            newValue.withByteCursor { valueCursor in
                _ = aws_http_message_set_request_path(rawValue, valueCursor)
            }
        }
    }

    /// Creates an http request which can be passed to a connection.
    /// - Parameters:
    ///   - method: Http method to use. Must be a valid http method and not empty.
    ///   - path: Path and query string for Http Request. Must not be empty.
    ///   - headers: (Optional) headers to send
    ///   - body: (Optional) body stream to send as part of request
    ///   - allocator: (Optional) allocator to override
    /// - Throws: CommonRuntimeError
    public init(method: String = "GET",
                path: String = "/",
                headers: [HTTPHeader] = [HTTPHeader](),
                body: IStreamable? = nil,
                allocator: Allocator = defaultAllocator) throws {
        guard let rawValue = aws_http_message_new_request(allocator.rawValue) else {
            throw CommonRunTimeError.crtError(.makeFromLastError())
        }
        super.init(rawValue: rawValue, allocator: allocator)

        self.method = method
        self.path = path
        self.body = body
        addHeaders(headers: headers)
    }

    override init(rawValue: OpaquePointer,
                  allocator: Allocator = defaultAllocator) {
       super.init(rawValue: rawValue, allocator: allocator)
    }
}

public class HTTP2Request: HTTPRequest {
    /// Creates an http2 request which can be passed to a connection.
    /// - Parameters:
    ///   - headers: (Optional) headers to send
    ///   - body: (Optional) body stream to send as part of request
    ///   - manualDataWrites: Set it to true to indicate body data will be provided over time.
    ///                       The data can be be supplied via `HTTP2Stream.writeData`.
    ///                       The last data should be sent with endOfStream as true to complete the stream.
    ///   - allocator: (Optional) allocator to override
    /// - Throws: CommonRuntimeError
    public init(headers: [HTTPHeader] = [HTTPHeader](),
                body: IStreamable? = nil,
                allocator: Allocator = defaultAllocator) throws {

        guard let rawValue = aws_http2_message_new_request(allocator.rawValue) else {
            throw CommonRunTimeError.crtError(.makeFromLastError())
        }
        super.init(rawValue: rawValue, allocator: allocator)

        self.body = body
        addHeaders(headers: headers)
    }
}
