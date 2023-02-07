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
        let encoded = try message.getEncodedSwift()

        let expectedEncoded = Data([ 0,0,0,126,0,0,0,93,54,26,172,142,13,58,109,101,115,115,97,103,101,45,116,121,112,101,7,0,5,101,118,101,110,116,11,58,101,118,101,110,116,45,116,121,112,101,7,0,15,77,101,115,115,97,103,101,87,105,116,104,66,108,111,98,13,58,99,111,110,116,101,110,116,45,116,121,112,101,7,0,24,97,112,112,108,105,99,97,116,105,111,110,47,111,99,116,101,116,45,115,116,114,101,97,109,104,101,108,108,111,32,102,114,111,109,32,75,111,116,108,105,110,23,206,234,17])
        XCTAssertEqual(expectedEncoded, encoded)
        
        let signature = Data([15,180,188,252,255,62,148,196,177,3,208,240,83,191,95,101,51,61,239,133,61,252,66,222,229,91,116,215,124,178,184,37])
        
        let date = Date(timeIntervalSince1970: 10)
        let newHeaders: [EventStreamHeader] = [
            .init(name: ":date", value: .timestamp(value: date)),
            .init(name: ":chunk-signature", value: .byteBuf(value: signature)),
        ]
        let signedMessage = EventStreamMessage(headers: newHeaders, payload: encoded)
        let encodedSignedMessage = try signedMessage.getEncodedSwift()
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
    
    func testOneMoreTime() {
        let headers: [EventStreamHeader] = [
            .init(name: ":message-type", value: .string(value: "event")),
            .init(name: ":event-type", value: .string(value: "AudioEvent")),
            .init(name: ":content-type", value: .string(value: "application/octet-stream"))
        ]
        let payload = "524946466c87010057415645666d74201000000001000100401f0000803e00000200100064617461de8601000100feff0200ffff000000000100feff0300fcff0400fdff0100000000000100feff01000000000000000100fdff0500faff0500fdff01000100feff0200ffffffff0200ffff00000000ffff0200ffff0100feff01000100feff0300fcff0400fdff0200feff0200feff0200feff0200feff0200feff01000000ffff0200fdff0400fbff0500fcff0300feff0100ffff0200fdff0300feff000001000000ffff0200feff010000000000ffff0200feff0200feff0100ffff0200feff01000000ffff0200fdff02000000ffff0100ffff00000100ffff0100ffff00000100ffff0100ffff00000100feff0300fdff0200ffff00000100feff0300fcff0400feff00000100ffffffff0300fdff02000000feff0200feff0200ffff0100feff0300fcff0500fbff03000000feff0300fdff0300fdff0300fcff0500fcff0300feff00000200fdff0300fdff0300ffffffff0100ffff0200feff0200fdff0400fdff0200feff0200feff0200feff0200feff0300fbff0500fbff0600fbff0300feff00000200feff01000000ffff01000000ffff010000000000ffff01000000000000000000000000000000ffff0200feff0200feff0200feff01000000ffff0300fcff0300feff0100000000000000ffff0200feff010000000000ffff0300fbff0500fdff00000300fcff0300ffff000000000000ffff0200ffff0100feff0200feff01000100feff0200feff0200feff0300fcff0400fdff02000000feff0200ffff00000100ffff000000000100feff0300fdff0200ffff000000000100feff0300fcff03000000feff0300fcff0400feff00000200fcff0500fbff0400fdff0300fdff0200ffff0100ffff0100ffff0100ffff0200feff0200feff01000000000000000000000000000000000000000000000000000000ffff0300fbff0600f9ff0700faff0500fcff0300fdff0300feff0200feff0100ffff0200feff0200fdff0300feff0100ffff0100feff0300fdff0200ffff00000000ffff0300fcff0400fbff0400feff0100ffff000000000000ffff0100feff0200feff0100ffff0200fdff0200ffff01000000ffff0000010000000000ffff00000100ffff0300fdff0200ffff00000100feff0200feff0000000000000200ffff000000000200fdff0300fcff0200000000000100feff0300fcff0400fdff0500fbff0100fefffeff040002000200ffff07000100fbff0200f9ff000001000700feff0000ffff0000010003000100fbff0200feff0200feff0700ffff0200040002000200fcff0200fbfffdfffbfffaff0300020003000600feff0000f9fffcfffcfffbfffefffefffdff0000fefffefffcff0300f9ff0b00fcfff7ff0400020007000100faffecfff9ff1c001000f2ff0f00e2ffdeff2000f8ffd8ff07002800170009000d00eafff3fff3fff9ff080005001d0024000e0000000200deffdbff1300cfffaaff3d005e00f0ff0800f8ffbeffe9fff4fff1ff2900440017000000c8ffa1ff1d005200fdff0c000b00f3ff2100d7ff92fffcff45006d006100cffffeff9c003f007dffc9ff02000c0026002c0046000800ddff95ffb3ff260061003700e3ffccffd2ff1400e0ffeeffb600e30081ffe4fe6d00270014ff7b000b01f3ffcaff2300feff88ff370098ff4cff8c00390066ff9effd000a1009aff48ff4f004500adffc6003d00c2ff98ffd5ff2dff68ff21013c006aff97ff0500b7ff83ff6300eeff42fffd00830098ffae007cffd1fe69ffac00d6002c00b5007d0090ff21ff73ff1700a3ff80009101a3fe65ff7c0133001f0186005fff47ff68ff7600bfffabff29012a00eefe45002101ad0088fea7fe9601f1ff46fe9100b9002b00ae004f004e00c4ffdeff85ff46fe3d003d029000d9feecff050089008000a7fec4ffd2ffceff2f00d7ffe600a0ff4eff79006afe0bfea000d401d6002cff000033ff66fea501a300c7fe2301a6010cff0dfebbff69007500c100d8ffe8ffeb0087fff9fe5800b201b7006dfe42ffc5ffadff6100c401a501eaffc5ff23febbfdb4ffa7018f017aff38003c003efeadfea5000b020202020014ff7dfe84fe19012d012a003301bfffa4fd92ff000175ff66ff4901d700aeff560094ff76ffc8fea2ff4302df0020005fff2ffe0dff8100fa01720221ff24fd0e00a1ffeefe0d00a001c30281001201300027fdb2fe830060ffcfffab01ec007e0266012cfed2ffacfd99fd1a021f009900470216fe70ff5d0125ff1eff5efecafe24005e00f300ab00bffff0fefdfd8100fc01a4fe99ffb90088ff4300820035005500cf013e006ffe90fe8afe5c009400e80036ff94ff6b0153fecefec30011018a00c6fffaffc0ff2bff88ff140343023efecdfe2f000c0051009701a7fe70ff8503e0ff18ff9f0053ffab014cfff4fb49ff72ff630111046eff68fea3ff55fe1c00abffe0fd2a00d0ffe9ffc4029fff7cfe9eff31fe4b000d015b006e0054ffb300b200aeff17009ffeadff420222006fff290067009402fe010701d7ff61fe58ff4100f00096ff83fdcafd8200f9009afee3fffa00d200c1fe11fd2e00b3000efea9ff8601aeff53014e0010fe70004eff96ff6c01f5008602100279006300450108026c016fffadff3c025d011101aa018700c000e9ffc2fbacfb32fd6cfcebfd6efee2fb41fb3efd46fe3afd7ffcf6fc2dffc3ffaefddf00ec025e01b101970196021f064906e1041b051e04fa036506c40556052a060104a702ff00a8010f02bf00c1ff2bfd66f9f5f418f30bf735f9b8f5def394f308f3cbf9b4fa99f810ff32ffd0fea2013004b105d705e109430d500d4b0ec30e2b0d390c950ca508b2065307e4067c07d4056b023a016bfc61f5b7ee31ea78f006f5c3f3e9f021eb70ecedec1beccff1aef345fbd801570165043a08550a360f74135c1320125614c014ed1307157b119e0d840c210b2a09bb063203df01a6fcb2f552ec0ce691e9baedb1ece1eab4e7e2e6c7e8b3e7d0e739ee8af79d00f107670b7f109410c60fa910cd0d2e0dc6108513a4157315ae12770f921077102e0d7608fe010a000001acff22fd41f6e5ecb6ea46ecffeb3ce92be407e2dfe4f7e5aee9fcecbceeadfbb10caf10ee10110b0606e10bc40fb40f7c10cc113816da174c13a40efe09a907dd0d24151b0ce8029ffeb8fd6c04baff81f358ef12e890ea0bed6de6b7e70be585e30de6e7e44de8bfeb6cf9fd0f0316d215a10d03055d0add0e30117411c40e72177c1b3f16a412f00afd05f60b1710060be40357ffa3ff540390ff03f7d3ef5ce9d8e922e882e747e885e6e1e54ee2fde054e4fbe6b7f81f0d7f18231ba70f04084009890b880ea00cf40bf414ed1b901d7a187f10df0a94090d09f806fe02b201ca0253026cfe0cf838f277ec02e848e610e856eae9e6f6e345e467e3ece65fe8f8efff065b16c01b86171f08f605050bd90d7d12030fe90d8017331b341bd9149f0b3e0ae108d506de04d9ffb4ff6400c2fefcfb19f4a6eeb1e9e0e78ce8a3e787e59fe5d8e49ee371e7b9e9b2ead4fbfc0dc618751d59113e0ad0089f0a1612ee10b20ecf12e1159f1a03183010d809d309d90b3a075002bcfddafeb901ecfe76fa2ff3a9ea9ae8bde711e7d5e74fe69ee459e554e4d1e5c8e8d2eceeffc910c3174a1a9c11ca0cdd0d6c0ea411690f530ed81185147e1872150e104e0a6707680b9c0a73051401c8fc6bfc23fc1af8e1f39eec0ee932ea0fea2feac4e7a5e223e346e367e5c3e89ded83fed50c1c1566191f139d0ffe106c1196146810ca0d800f150f5013f213010f9d0ca808b109e30ddf07c30394ff9efaa7fbaaf762f2ebef21eb3bec15ecf8e84ee7f9e299e3b1e46be5e7e6d5e939f76b065810ba17d4148d12e315cd1579160a14200f6f0ef50d030ebb0f490c0a0b8e0a8708810b260c5b09e6061c00d4fb6df9c9f3b3f1b7ed5aea70ea9ee86ce869e8dee429e41ae400e408e7d9ed18fb4f08ff100d15941494159e18fa18b3186014540f420e8a0d430e850d840a3009240852093a0d3d0d8e0a6a04e2fd0dfa53f7bef461f00bec5eea6ce9bae948e988e668e59ce375e3cde45fe7dcf00cfebe082b117c1301140c178918bf1a7319e613da105a0e310d720e9a0b83090408f7053f088e0b810d3a0c0306aafe3ef908f6cef3d5ef9aec4eea17e9abe857e757e6cbe599e4d0e452e54ae8a7f2f4fe1e0ac3115a130214ce150418b61a3d1951150c11430dfd0ceb0cf50a90080c0699046e064c0b990e830ced0641ff32f986f6edf3dff017ed96e96be899e759e789e712e694e50ce6f8e56eea46f4f3fe8309b310b7128f13f5142a18251bf0192716ee10510d100d4a0cb90afd07fa04b60470068f0ac90d720ce60770018ffb73f8a3f5e5f1a9edede9f2e711e8c0e70ee72ee6c6e551e61ce6ede97af3b2fd4208540fa91089126f142f189d1bb419c9157811de0de70c9c0a0a080c060d040a0524078209cb0bd10af0068c027ffd30fac0f6f1f14cedd5e997e801e9c0e853e87ee674e5b9e550e638ec56f65f00b3095f0eee0f8e122e156b19f01bfc1936169f11410ee10c5b0aa3083d068603bb035e05e807d50a200aca075f03b3fd9ff98ef574f1a3ed86e94de798e676e641e773e670e5e1e300e544ec89f78702080bab0d8e0fc812b3160e1b341cad1845144310520ed30dae0bef08030571020b03db059e08430ac30871063f0310004ffcf6f7b4f285ed4ce952e7cde6a1e62ee613e5dbe34ae38be7fff04ffc3a06af0cb00e7c1157157919e71b7a1afb15d3113f0e7a0ca30ada07b104080234018c0297042607dd0844087506e5020fff4efb6ef71af32dee3be934e729e6f8e525e5c6e366e244e3b7ea7cf77d02dd0a9d0e8c0f731338185e1cde1c18187312720e610c9b0c140a3a06c0018dfe75ff8302f605080905091a0864058c010aff2ffb33f715f37bedc8e9fce7f0e6f5e61ae5cfe31ae2a2e3aeed99f97604d20cd00e821179155e19071c331ab415bf112e0de40ac80997064604bf004ffff6ff0001db04dd071d094d097406150396ffabfaf2f653f380ee04ec31e986e773e694e5fee4a6e2aae4b9ee9cfaaf06490e750f8511e314c319ea1c531ab214c70f120c510a65088505db01d7fdfdfc3dfe88ffe60213064809f50abb0801055e008cfb46f8c1f46cf064ed03eb69ea1de94fe75be50ee28ae40eef1afbfd06fc0da30ffb112314bb179f1ae0170013b00d3809ab0743050604ee0129fe07fe56ffe400e603da0585086b0bc709b4065901d8fa1cf837f51ff3e1f086ec04ea7de76ce60ee783e427e366eafef44202270d3c10991123127415dd195a19f914f80ebd087106ee046604bb0211ff0efdd5fd16015d04b208920aa50a2208a404410219febcfad4f752f4aaf010ee92eb73e97fe803e6ace45ae046e572f218ffef0bf40fcf10e312c5156e18d4187213800ec70a7d07490787056002b90064fef9fe9603ad04e308240c420bfb08c6038700d5fde0fa62f9d7f5f6ee9eeb0cea80e9abebbae870e773e05fe1b1f068fe100d6f11d61093105e13db152619aa15a30e5a0a10043605bc074e067805670134ffec064c0ac00d480e210764020efe9afa60fbfbf7a2f69cf4ccec18eb47e9b1e6a5ea69e653e58edf30e092faf90cae1c121d"
        let message = EventStreamMessage(headers: headers, payload: payload.decodeHexBytes(), allocator: allocator)
        let encoded = try! message.getEncoded()
        // write encoded to file
        var filePath = "/Users/jangirg/Projects/Amplify/SwiftSDK/aws-crt-swift/Test/AwsCommonRuntimeKitTests/event-stream/swift.output"
        // reduce array to string with new line separator
        let text = encoded.toBytes().reduce("") { $0 + String($1) + "\n" }
        text.write(to: &filePath)
    }
}

extension String {
    func decodeHexBytes() -> Data {
        var data = Data(capacity: self.count / 2)
        var index = self.startIndex
        for _ in 0..<(self.count / 2) {
            let nextIndex = self.index(index, offsetBy: 2)
            let byteString = self[index..<nextIndex]
            index = nextIndex
            var num = UInt8(byteString, radix: 16)!
            data.append(&num, count: 1)
        }
        return data
    }
}
