//
//  ByteBuffer.swift
//  Zeno
//
//  Created by Angelo Corsaro on 26/04/2017.
//
//

import Foundation

enum ByteBufferError : Error {
    case OverFlow
    case Underflow
    case InvalidFormat
}


open class ByteBuffer : CustomStringConvertible {
    
    private var buf_: [UInt8]
    private var position_ = 0
    private var limit_ = 0
    
    public var description: String {
        return "ByteBuffer[pos=\(self.position), lim=\(self.limit), cap=\(self.capacity)]"
    }
    public var position: Int {
        get {
            return self.position_
        }
        set(newPos) {
            precondition(newPos < self.buf_.capacity)
            self.position_ = newPos
        }
    }
    
    public var limit: Int {
        get {
            return self.limit_
        }
        set(newLimit) {
            precondition((newLimit <= self.buf_.capacity) && (self.position <= newLimit))
            self.limit_ = newLimit
        }
    }
    
    var capacity: Int {
        get {
            return self.buf_.capacity
        }
    }
    
    public var remaining: Int {
        get {
            return self.limit - self.position
        }
    }
    
    public init(_ s: Int) {
        self.buf_ = [UInt8](repeating: 0, count: s)
        self.position = 0
        self.limit = buf_.capacity
        
    }
    
    /*
     * Wraps an existing array with a byte buffer
     */
    public init(fromArray xs: [UInt8]) {
        self.buf_ = xs
        self.position = 0
        self.limit = buf_.capacity
    }
    
    public init(fromData d: Data) {
        self.buf_ = [UInt8](d)
        self.position = 0
        self.limit = self.buf_.capacity
    }
    
    public func getSlice() -> ArraySlice<UInt8> {
        return self.buf_[self.position..<self.limit]
    }
    
    public func getData() -> Data {
        return Data(self.buf_[self.position..<self.limit])
    }
    
    public func getBuf() -> [UInt8] {
        return self.buf_
    }
    
    public func getUnsafeMutablePointer() -> UnsafeMutablePointer<UInt8> {
        var ptr = UnsafeMutablePointer(&buf_[0])
        if self.position != 0 {
            ptr = ptr.advanced(by: self.position)
        }
        return ptr
    }
    
    @discardableResult
    public func clear() -> ByteBuffer {
        self.position = 0
        self.limit = self.capacity
        return self
    }
    
    @discardableResult
    public func flip() -> ByteBuffer {
        let p = self.position
        self.position = 0
        self.limit = p
        return self
    }
    
    @discardableResult
    public func put(byte b: UInt8) throws -> ByteBuffer {
        if (self.position >= self.limit) { throw ByteBufferError.OverFlow }
        self.buf_[self.position] = b
        self.position = self.position + 1
        return self
    }
    
    public func getByte() throws -> UInt8 {
        if (self.position >= self.limit) { throw ByteBufferError.Underflow }
        let v = self.buf_[self.position]
        self.position += 1
        return v
    }
    
    
    
    @discardableResult
    public func put(bytes bs: [UInt8]) throws -> ByteBuffer {
        let len = bs.endIndex
        if (self.remaining < len) { throw ByteBufferError.OverFlow }
        let start = self.position
        let end = start + len
        self.buf_[start..<end] = bs[0..<len]
        self.position = self.position + len
        return self
    }
    
    public func getBytes() throws -> [UInt8] {
        let len = Int(try self.getVle())
        return try self.getBytes(len)
    
    }
    public func getBytes(_ n: Int) throws -> [UInt8] {
        if (self.position + n > self.limit) { throw ByteBufferError.Underflow }
        var bs =  [UInt8](repeating: 0, count: n)
        bs[0..<n] = self.buf_[self.position..<self.position+n]
        self.position += n
        return bs
    }
    
    @discardableResult
    public func put(uint16 v: UInt16) throws -> ByteBuffer {
        if (self.position + 2 > self.limit) { throw ByteBufferError.OverFlow }
        let lev = v.littleEndian
        
        try! self.put(byte: UInt8(lev & 0xff))
        try! self.put(byte: UInt8(lev >> 8))
        
        return self
    }
    
    public func getUInt16() throws -> UInt16 {
        if (self.position + 2 > self.limit) { throw ByteBufferError.Underflow }
        var v: UInt16 = 0
        v = UInt16(try! self.getByte()) | (UInt16(try! self.getByte()) << 8)
        return UInt16(littleEndian: v)
    }
    
    @discardableResult
    public func put(vle v: UInt) throws -> ByteBuffer {
        if (self.position+1 > self.limit) { throw ByteBufferError.OverFlow }
        if (v <= 0x7f) {
            try! self.put(byte: UInt8(v))
        } else {
            let b = UInt8((v & 0x7f) | 0x80)
            try! self.put(byte: b)
            try self.put(vle: (v >> 7))
        }
        return self
    }
    
    public func getVle() throws -> UInt {
        
        func agetVle(_ a: UInt, _ n: UInt) throws -> UInt {
            let b = try self.getByte()
            var r = UInt(0)
            
            if (b <= 0x7f) {
                let shift = n*7
                let u = UInt(b) << shift
                r = u | a
            } else {
                r = (UInt(b & 0x7f) << (n * 7)) | a
                r = try agetVle(r, n+1)
            }
            return r
        }
        return try agetVle( 0, 0)
    }
    
    @discardableResult
    public func put(string s: String) throws -> ByteBuffer {
        let bs: [UInt8] = Array(s.utf8)
        let len = bs.endIndex
        if (self.position+len > self.limit) { throw ByteBufferError.OverFlow }
        try! self.put(vle: UInt(len))
        try! self.put(bytes: bs)
        return self
    }
    
    @discardableResult
    public func put(stringArray xs: [String]) throws -> ByteBuffer {
        let len = xs.endIndex
        if (self.position+len > self.limit) { throw ByteBufferError.OverFlow }
        try self.put(vle: UInt(len))
        try xs.forEach { x in try self.put(string: x) }
        return self
    }
    
    public func getStringArray() throws -> [String] {
        let len = Int(try self.getVle())
        var xs = [String](repeating: "", count: len)
        for i in 0..<len {
            if let x = try self.getString() {
                xs[i] = x                
            }
        }
        return xs
    }
    
    public func getString() throws -> String? {
        let len = Int(try self.getVle())
        let bs = try self.getBytes(len)
        return String(data: Data(bs), encoding: .utf8)
    }
}
