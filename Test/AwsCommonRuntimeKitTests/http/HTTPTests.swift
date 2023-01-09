//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0.

import XCTest
@testable import AwsCommonRuntimeKit
import AwsCCommon
import AwsCHttp

class HTTPTests: HTTPClientTestFixture {
    let host = "httpbin.org"
    let destination = URL(string: "https://httpbin.org/get")!

    func testGetHTTPSRequest() async throws {
        let test: URL
        let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
        do {
            _ = try await sendHTTPRequest(method: "GET", destination: destination, connectionManager: connectionManager)
        } catch {
            print ("waahm7\(error)")
            throw error
        }
            _ = try await sendHTTPRequest(method: "GET", destination: URL(string: "https://httpbin.org/delete")!, expectedStatus: 405, connectionManager: connectionManager)
    }

    func testGetHTTPRequest() async throws {
        let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: false, port: 80)
        _ = try await sendHTTPRequest(method: "GET", destination: destination, connectionManager: connectionManager)
    }

    func testPutHttpRequest() async throws {
        let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
        let response = try await sendHTTPRequest(
                method: "PUT",
                destination: URL(string: "https://httpbin.org/anything")!,
                body: TEST_DOC_LINE,
                connectionManager: connectionManager)

        // Parse json body
        struct Response: Codable {
            let data: String
        }
        let body: Response = try! JSONDecoder().decode(Response.self, from: response.body)
        XCTAssertEqual(body.data, TEST_DOC_LINE)
    }

    func testHTTPStreamIsReleasedIfNotActivated() async throws {
        do {


            let httpRequestOptions = try getHTTPRequestOptions(method: "GET", destination: destination, headers: [HTTPHeader(name: "host", value: destination.host!)])
            let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
            let connection = try await connectionManager.acquireConnection()
            _ = try connection.makeRequest(requestOptions: httpRequestOptions)
        } catch let err {
            print(err)
        }
    }

    func testStreamLivesUntilComplete() async throws {
        let semaphore = DispatchSemaphore(value: 0)

        do {
            let httpRequestOptions = try getHTTPRequestOptions(method: "GET", destination: destination, semaphore: semaphore)
            let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
            let connection = try await connectionManager.acquireConnection()
            let stream = try connection.makeRequest(requestOptions: httpRequestOptions)
            try stream.activate()
        }
        semaphore.wait()
    }

    func testManagerLivesUntilComplete() async throws {
        var connection: HTTPExchange! = nil
        let semaphore = DispatchSemaphore(value: 0)

        do {
            let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
            connection = try await connectionManager.acquireConnection()
        }
        let httpRequestOptions = try getHTTPRequestOptions(method: "GET", destination: destination, semaphore: semaphore, headers: [HTTPHeader(name: "host", value: destination.host!)])
        let stream = try connection.makeRequest(requestOptions: httpRequestOptions)
        try stream.activate()
        semaphore.wait()
    }

    func testConnectionLivesUntilComplete() async throws {
        var stream: HTTPStream! = nil
        let semaphore = DispatchSemaphore(value: 0)

        do {
            let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
            let connection = try await connectionManager.acquireConnection()
            let httpRequestOptions = try getHTTPRequestOptions(method: "GET", destination: destination, semaphore: semaphore)
            stream = try connection.makeRequest(requestOptions: httpRequestOptions)
        }
        try stream.activate()
        semaphore.wait()
    }

    func testConnectionCloseThrow() async throws {
        let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
        let connection = try await connectionManager.acquireConnection()
        connection.close()
        let httpRequestOptions = try getHTTPRequestOptions(method: "GET", destination: destination)
        XCTAssertThrowsError( _ = try connection.makeRequest(requestOptions: httpRequestOptions))
    }

    func testConnectionCloseActivateThrow() async throws {
        let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
        let connection = try await connectionManager.acquireConnection()
        let httpRequestOptions = try getHTTPRequestOptions(method: "GET", destination: destination)
        let stream = try connection.makeRequest(requestOptions: httpRequestOptions)
        connection.close()
        XCTAssertThrowsError(try stream.activate())
    }

    func testConnectionCloseIsIdempotent() async throws {
        let connectionManager = try await getHttpConnectionManager(endpoint: host, ssh: true, port: 443)
        let connection = try await connectionManager.acquireConnection()
        let httpRequestOptions = try getHTTPRequestOptions(method: "GET", destination: destination)
        let stream = try connection.makeRequest(requestOptions: httpRequestOptions)
        connection.close()
        connection.close()
        connection.close()
        XCTAssertThrowsError(try stream.activate())
    }
}
