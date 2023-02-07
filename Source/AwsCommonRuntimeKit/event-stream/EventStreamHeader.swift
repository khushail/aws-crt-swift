//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0.

import AwsCEventStream
import Foundation

extension Data {
    
    public func toBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: self.count)
        self.copyBytes(to:&bytes, count: self.count * MemoryLayout<UInt8>.size)
        return bytes
    }
}

func _convertToBytes<T>(_ value: T, withCapacity capacity: Int) -> [UInt8] {
    
    var mutableValue = value
    return withUnsafePointer(to: &mutableValue) {
        
        return $0.withMemoryRebound(to: UInt8.self, capacity: capacity) {
            
            return Array(UnsafeBufferPointer(start: $0, count: capacity))
        }
    }
}

extension UnsignedInteger {
    
    var bytes: [UInt8] {
        
        return _convertToBytes(self, withCapacity: MemoryLayout<Self>.size)
    }
    
    init?(_ bytes: [UInt8]) {
        
        guard bytes.count == MemoryLayout<Self>.size else { return nil }
        
        self = bytes.withUnsafeBytes {
            
            return $0.load(as: Self.self)
        }
    }
}

extension SignedInteger {
    
    var bytes: [UInt8] {
        
        return _convertToBytes(self, withCapacity: MemoryLayout<Self>.size)
    }
    
    init?(_ bytes: [UInt8]) {
        
        guard bytes.count == MemoryLayout<Self>.size else { return nil }
        
        self = bytes.withUnsafeBytes {
            
            return $0.load(as: Self.self)
        }
    }
}

extension FloatingPoint {
    
    var bytes: [UInt8] {
        
        return _convertToBytes(self, withCapacity: MemoryLayout<Self>.size)
    }
    
    init?(_ bytes: [UInt8]) {
        
        guard bytes.count == MemoryLayout<Self>.size else { return nil }
        
        self = bytes.withUnsafeBytes {
            
            return $0.load(as: Self.self)
        }
    }
}


public struct EventStreamHeader {
    /// max header name length is 127 bytes (Int8.max)
    public static let maxNameLength = AWS_EVENT_STREAM_HEADER_NAME_LEN_MAX

    public static let maxValueLength = Int16.max

    /// name.count can not be greater than EventStreamHeader.maxNameLength
    public var name: String

    /// value.count can not be greater than EventStreamHeader.maxValueLength for supported types.
    public var value: EventStreamHeaderValue

    public init(name: String, value: EventStreamHeaderValue) {
        self.name = name
        self.value = value
    }

    public func getEncodedSwift() throws -> Data {
        var encoded = Data()
        let nameBytes = name.data(using: .utf8)!
        let nameBytesCount = Int32(nameBytes.count)
        encoded.append(contentsOf: nameBytesCount.bigEndian.bytes)
        encoded.append(nameBytes)
        encoded.append(try value.getEncodedSwift())
        
        return encoded
    }
}

public enum EventStreamHeaderValue: Equatable {
    case bool(value: Bool)
    case byte(value: Int8)
    case int16(value: Int16)
    case int32(value: Int32)
    case int64(value: Int64)
    /// Data length can not be greater than EventStreamHeader.maxValueLength
    case byteBuf(value: Data)
    /// String length can not be greater than EventStreamHeader.maxValueLength
    case string(value: String)
    /// Date is only precise up to milliseconds.
    /// It will lose the sub-millisecond precision during encoding.
    case timestamp(value: Date)
    case uuid(value: UUID)

    public func getEncodedSwift() throws -> Data {
        var encoded = Data()
        switch self {
        case .byteBuf(let value):
            encoded.append(contentsOf: Int32(6).bigEndian.bytes)
            encoded.append(contentsOf: Int32(value.count).bigEndian.bytes)
            encoded.append(value)
        case .string(let value):
            encoded.append(contentsOf: Int32(7).bigEndian.bytes)
            encoded.append(contentsOf: Int32(value.count).bigEndian.bytes)
            encoded.append(value.data(using: .utf8)!)
        case .timestamp(let value):
            encoded.append(contentsOf: Int32(8).bigEndian.bytes)
            let milliseconds = Int64(value.timeIntervalSince1970 * 1000)
            encoded.append(contentsOf: milliseconds.bigEndian.bytes)
        default:
                fatalError()
        }
        
        return encoded
    }
}

extension EventStreamHeaderValue {
    static func parseRaw(rawValue: UnsafeMutablePointer<aws_event_stream_header_value_pair>) -> EventStreamHeaderValue {
        let value: EventStreamHeaderValue
        switch rawValue.pointee.header_value_type {
        case AWS_EVENT_STREAM_HEADER_BOOL_TRUE:
            value = .bool(
                value: aws_event_stream_header_value_as_bool(rawValue) != 0)
        case AWS_EVENT_STREAM_HEADER_BOOL_FALSE:
            value = .bool(
                value: aws_event_stream_header_value_as_bool(rawValue) != 0)
        case AWS_EVENT_STREAM_HEADER_BYTE:
            value = .byte(value: aws_event_stream_header_value_as_byte(rawValue))
        case AWS_EVENT_STREAM_HEADER_INT16:
            value = .int16(
                value: aws_event_stream_header_value_as_int16(rawValue))
        case AWS_EVENT_STREAM_HEADER_INT32:
            value = .int32(
                value: aws_event_stream_header_value_as_int32(rawValue))
        case AWS_EVENT_STREAM_HEADER_INT64:
            value = .int64(
                value: aws_event_stream_header_value_as_int64(rawValue))
        case AWS_EVENT_STREAM_HEADER_BYTE_BUF:
            value = .byteBuf(
                value: aws_event_stream_header_value_as_bytebuf(rawValue).toData())
        case AWS_EVENT_STREAM_HEADER_STRING:
            value = .string(
                value: aws_event_stream_header_value_as_string(rawValue).toString())
        case AWS_EVENT_STREAM_HEADER_TIMESTAMP:
            value = .timestamp(
                value: Date(
                    millisecondsSince1970: aws_event_stream_header_value_as_timestamp(rawValue)))
        case AWS_EVENT_STREAM_HEADER_UUID:
            let uuid = UUID(uuid: rawValue.pointee.header_value.static_val)
            value = .uuid(value: uuid)
        default:
            fatalError("Unexpected header value type found.")
        }
        return value
    }
}

extension EventStreamHeader: Equatable {
    public static func == (lhs: EventStreamHeader, rhs: EventStreamHeader) -> Bool {
        if case let EventStreamHeaderValue.timestamp(value1) = lhs.value,
           case let EventStreamHeaderValue.timestamp(value2) = rhs.value {
            return lhs.name == rhs.name &&
                value1.millisecondsSince1970 == value2.millisecondsSince1970
        }
        return lhs.name == rhs.name &&
            lhs.value == rhs.value
    }
}
