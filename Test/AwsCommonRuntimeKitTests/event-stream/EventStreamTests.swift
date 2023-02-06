//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0.

import XCTest
import AwsCEventStream
@testable import AwsCommonRuntimeKit

class EventStreamTests: XCBaseTestCase {
    let semaphore = DispatchSemaphore(value: 0)

    func testEncodeDecodeHeaders() async throws {
        let onCompleteWasCalled = XCTestExpectation(description: "OnComplete was called")

        let headers = [
            EventStreamHeader(name: "bool", value: .bool(value: true)),
            EventStreamHeader(name: "byte", value: .byte(value: 16)),
            EventStreamHeader(name: "int16", value: .int32(value: 16)),
            EventStreamHeader(name: "int32", value: .int32(value: 32)),
            EventStreamHeader(name: "int64", value: .int32(value: 64)),
            EventStreamHeader(name: "byteBuf", value: .byteBuf(value: "data".data(using: .utf8)!)),
            EventStreamHeader(name: "host", value: .string(value: "aws-crt-test-stuff.s3.amazonaws.com")),
            EventStreamHeader(name: "host", value: .string(value: "aws-crt-test-stuff.s3.amazonaws.com")),
            EventStreamHeader(name: "bool", value: .bool(value: false)),
            EventStreamHeader(name: "timestamp", value: .timestamp(value: Date(timeIntervalSinceNow: 10))),
            EventStreamHeader(name: "uuid", value: .uuid(value: UUID(uuidString: "63318232-1C63-4D04-9A0C-6907F347704E")!)),
        ]
        let message = EventStreamMessage(headers: headers, allocator: allocator)
        let encoded = try message.getEncoded()
        var decodedHeaders = [EventStreamHeader]()
        let decoder = EventStreamMessageDecoder(
                onPayloadSegment: { payload, finalSegment in
                    XCTFail("OnPayload callback is triggered unexpectedly.")
                },
                onPreludeReceived: { totalLength, headersLength in
                    XCTAssertEqual(totalLength, 210)
                    XCTAssertEqual(headersLength, 194)
                },
                onHeaderReceived: { header in
                    decodedHeaders.append(header)
                },
                onComplete: {
                    onCompleteWasCalled.fulfill()
                },
                onError: { code, message in
                    XCTFail("Error occurred. Code: \(code)\nMessage:\(message)")
                })
        try decoder.decode(data: encoded)
        XCTAssertTrue(headers.elementsEqual(decodedHeaders))
        wait(for: [onCompleteWasCalled], timeout: 1)
    }

    func testEncodeDecodePayload() async throws {
        let onCompleteWasCalled = XCTestExpectation(description: "OnComplete was called")

        let payload = "payload".data(using: .utf8)!
        let message = EventStreamMessage(payload: payload, allocator: allocator)
        let encoded = try message.getEncoded()
        var decodedPayload = Data()
        let decoder = EventStreamMessageDecoder(
                onPayloadSegment: { payload, finalSegment in
                    decodedPayload.append(payload)
                },
                onPreludeReceived: { totalLength, headersLength in
                    XCTAssertEqual(totalLength, 23)
                    XCTAssertEqual(headersLength, 0)
                },
                onHeaderReceived: { header in
                    XCTFail("OnHeader callback is triggered unexpectedly.")
                }, onComplete: {
                    onCompleteWasCalled.fulfill()
                },
                onError: { code, message in
                    XCTFail("Error occurred. Code: \(code)\nMessage:\(message)")
                })
        try decoder.decode(data: encoded)
        XCTAssertEqual(payload, decodedPayload)
        wait(for: [onCompleteWasCalled], timeout: 1)
    }

    func testEncodeOutOfScope() async throws {
        let onCompleteWasCalled = XCTestExpectation(description: "OnComplete was called")

        let encoded: Data
        do {
            let headers = [EventStreamHeader(name: "int16", value: .int32(value: 16))]
            let payload = "payload".data(using: .utf8)!
            let message = EventStreamMessage(headers: headers, payload: payload, allocator: allocator)
            encoded = try message.getEncoded()
        }

        var decodedPayload = Data()
        var decodedHeaders = [EventStreamHeader]()

        let decoder = EventStreamMessageDecoder(
                onPayloadSegment: { payload, finalSegment in
                    decodedPayload.append(payload)
                },
                onPreludeReceived: { totalLength, headersLength in
                    XCTAssertEqual(totalLength, 34)
                    XCTAssertEqual(headersLength, 11)
                },
                onHeaderReceived: { header in
                    decodedHeaders.append(header)
                }, onComplete: {
                    onCompleteWasCalled.fulfill()
                },
                onError: { code, message in
                    XCTFail("Error occurred. Code: \(code)\nMessage:\(message)")
                })
        try decoder.decode(data: encoded)
        XCTAssertEqual("payload".data(using: .utf8), decodedPayload)

        let expectedHeaders = [EventStreamHeader(name: "int16", value: .int32(value: 16))]
        XCTAssertTrue(expectedHeaders.elementsEqual(decodedHeaders))
        wait(for: [onCompleteWasCalled], timeout: 1)
    }

    func testDecodeByteByByte() async throws {
        let onCompleteWasCalled = XCTestExpectation(description: "OnComplete was called")

        let headers = [EventStreamHeader(name: "int16", value: .int32(value: 16))]
        let payload = "payload".data(using: .utf8)!
        let message = EventStreamMessage(headers: headers, payload: payload, allocator: allocator)
        let encoded = try message.getEncoded()

        var decodedPayload = Data()
        var decodedHeaders = [EventStreamHeader]()

        let decoder = EventStreamMessageDecoder(
                onPayloadSegment: { payload, finalSegment in
                    decodedPayload.append(payload)
                },
                onPreludeReceived: { totalLength, headersLength in
                    XCTAssertEqual(totalLength, 34)
                    XCTAssertEqual(headersLength, 11)
                },
                onHeaderReceived: { header in
                    decodedHeaders.append(header)
                }, onComplete: {
                    onCompleteWasCalled.fulfill()
                },
                onError: { code, message in
                    XCTFail("Error occurred. Code: \(code)\nMessage:\(message)")
                })
        for byte in encoded {
            try decoder.decode(data: Data([byte]))
        }

        XCTAssertEqual(payload, decodedPayload)
        XCTAssertTrue(headers.elementsEqual(decodedHeaders))
        wait(for: [onCompleteWasCalled], timeout: 1)
    }

    func testEmpty() async throws {
        let onCompleteWasCalled = XCTestExpectation(description: "OnComplete was called")

        let message = EventStreamMessage(allocator: allocator)
        let encoded = try message.getEncoded()
        let decoder = EventStreamMessageDecoder(
                onPayloadSegment: { payload, finalSegment in
                    XCTFail("OnPayload callback is triggered unexpectedly.")
                },
                onPreludeReceived: { totalLength, headersLength in
                    XCTAssertEqual(totalLength, 16)
                    XCTAssertEqual(headersLength, 0)
                },
                onHeaderReceived: { header in
                    XCTFail("OnHeader callback is triggered unexpectedly.")
                }, onComplete: {
                    onCompleteWasCalled.fulfill()
                },
                onError: { code, message in
                    XCTFail("Error occurred. Code: \(code)\nMessage:\(message)")
                })
        try decoder.decode(data: encoded)
        wait(for: [onCompleteWasCalled], timeout: 1)
    }
    
    func testAgainstExpectedResult() async throws {
        let headers: [EventStreamHeader] = [
            .init(name: ":message-type", value: .string(value: "event")),
            .init(name: ":event-type", value: .string(value: "MessageWithBlob")),
            .init(name: ":content-type", value: .string(value: "application/octet-stream")),
        ]
        let payload = "hello from Kotlin".data(using: .utf8)!
        let message = EventStreamMessage(headers: headers, payload: payload, allocator: allocator)
        let encoded = try message.getEncoded()

        let expectedEncoded = Data([ 0,0,0,126,0,0,0,93,54,26,172,142,13,58,109,101,115,115,97,103,101,45,116,121,112,101,7,0,5,101,118,101,110,116,11,58,101,118,101,110,116,45,116,121,112,101,7,0,15,77,101,115,115,97,103,101,87,105,116,104,66,108,111,98,13,58,99,111,110,116,101,110,116,45,116,121,112,101,7,0,24,97,112,112,108,105,99,97,116,105,111,110,47,111,99,116,101,116,45,115,116,114,101,97,109,104,101,108,108,111,32,102,114,111,109,32,75,111,116,108,105,110,23,206,234,17])
        XCTAssertEqual(expectedEncoded, encoded)
        
        let signature = Data([15,180,188,252,255,62,148,196,177,3,208,240,83,191,95,101,51,61,239,133,61,252,66,222,229,91,116,215,124,178,184,37])
        
        let date = Date(timeIntervalSince1970: 10)
        let newHeaders: [EventStreamHeader] = [
            .init(name: ":date", value: .timestamp(value: date)),
            .init(name: ":chunk-signature", value: .byteBuf(value: signature)),
        ]
        let signedMessage = EventStreamMessage(headers: newHeaders, payload: encoded)
        let encodedSignedMessage = try signedMessage.getEncoded()
        let expectedEncodedSignedMessage = Data([0,0,0,209,0,0,0,67,62,98,153,170,5,58,100,97,116,101,8,0,0,1,134,40,169,223,248,16,58,99,104,117,110,107,45,115,105,103,110,97,116,117,114,101,6,0,32,15,180,188,252,255,62,148,196,177,3,208,240,83,191,95,101,51,61,239,133,61,252,66,222,229,91,116,215,124,178,184,37,0,0,0,126,0,0,0,93,54,26,172,142,13,58,109,101,115,115,97,103,101,45,116,121,112,101,7,0,5,101,118,101,110,116,11,58,101,118,101,110,116,45,116,121,112,101,7,0,15,77,101,115,115,97,103,101,87,105,116,104,66,108,111,98,13,58,99,111,110,116,101,110,116,45,116,121,112,101,7,0,24,97,112,112,108,105,99,97,116,105,111,110,47,111,99,116,101,116,45,115,116,114,101,97,109,104,101,108,108,111,32,102,114,111,109,32,75,111,116,108,105,110,23,206,234,17,192,58,71,38])
        XCTAssertEqual(expectedEncodedSignedMessage, encodedSignedMessage)
    }
    
    func testSerializeMessageWithHeaders() async throws {
        let headers: [EventStreamHeader] = [
            .init(name: ":message-type", value: .string(value: "event")),
            .init(name: ":event-type", value: .string(value: "MessageWithHeaders")),
            .init(name: "blob", value: .byteBuf(value: "blobby".data(using: .utf8)!)),
            .init(name: "byte", value: .byte(value: 66)),
            .init(name: "short", value: .int16(value: 16_000)),
            .init(name: "int", value: .int32(value: 100_000)),
            .init(name: "long", value: .int64(value: 9_000_000_000)),
            .init(name: "timestamp", value: .timestamp(value: Date(timeIntervalSince1970: 5))),
        ]
        let message = EventStreamMessage(headers: headers, payload: .init(), allocator: allocator)
        let encoded = try message.getEncoded()

        let expectedEncoded = Data([0,0,0,179,0,0,0,163,125,154,95,255,13,58,109,101,115,115,97,103,101,45,116,121,112,101,7,0,5,101,118,101,110,116,11,58,101,118,101,110,116,45,116,121,112,101,7,0,18,77,101,115,115,97,103,101,87,105,116,104,72,101,97,100,101,114,115,4,98,108,111,98,6,0,6,98,108,111,98,98,121,7,98,111,111,108,101,97,110,0,4,98,121,116,101,2,55,3,105,110,116,4,0,1,134,160,4,108,111,110,103,5,0,0,0,2,24,113,26,0,5,115,104,111,114,116,3,62,128,6,115,116,114,105,110,103,7,0,17,97,32,116,97,121,32,105,115,32,97,32,104,97,109,109,101,114,9,116,105,109,101,115,116,97,109,112,8,0,0,0,0,0,0,19,136,152,131,32,119])
        XCTAssertEqual(expectedEncoded, encoded)
        
        let signature = Data([54,54,99,57,56,98,50,56,55,98,52,57,57,48,54,56,48,97,52,102,54,54,50,99,48,52,49,52,101,57,54,99,101,57,51,102,98,97,56,99,52,51,100,99,99,54,57,55,57,100,51,49,52,50,48,52,52,48,55,55,55,48,54,53])
        
        let date = Date(timeIntervalSince1970: 10)
        let newHeaders: [EventStreamHeader] = [
            .init(name: ":date", value: .timestamp(value: date)),
            .init(name: ":chunk-signature", value: .byteBuf(value: signature)),
        ]
        let signedMessage = EventStreamMessage(headers: newHeaders, payload: encoded)
        let encodedSignedMessage = try signedMessage.getEncoded()
        let expectedEncodedSignedMessage = Data([0,0,1,6,0,0,0,67,206,235,233,70,5,58,100,97,116,101,8,0,0,1,134,40,176,76,128,16,58,99,104,117,110,107,45,115,105,103,110,97,116,117,114,101,6,0,32,102,201,139,40,123,73,144,104,10,79,102,44,4,20,233,108,233,63,186,140,67,220,198,151,157,49,66,4,64,119,112,101,0,0,0,179,0,0,0,163,125,154,95,255,13,58,109,101,115,115,97,103,101,45,116,121,112,101,7,0,5,101,118,101,110,116,11,58,101,118,101,110,116,45,116,121,112,101,7,0,18,77,101,115,115,97,103,101,87,105,116,104,72,101,97,100,101,114,115,4,98,108,111,98,6,0,6,98,108,111,98,98,121,7,98,111,111,108,101,97,110,0,4,98,121,116,101,2,55,3,105,110,116,4,0,1,134,160,4,108,111,110,103,5,0,0,0,2,24,113,26,0,5,115,104,111,114,116,3,62,128,6,115,116,114,105,110,103,7,0,17,97,32,116,97,121,32,105,115,32,97,32,104,97,109,109,101,114,9,116,105,109,101,115,116,97,109,112,8,0,0,0,0,0,0,19,136,152,131,32,119,244,188,113,13])
        XCTAssertEqual(expectedEncodedSignedMessage, encodedSignedMessage)
    }
}
