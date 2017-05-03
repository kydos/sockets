import libc

public protocol TCPWriteableSocket: TCPSocket, WriteableStream { }

extension TCPWriteableSocket {
    public func write(_ data: Bytes) throws {
        let len = data.count
        let sentLen = libc.send(descriptor.raw, data, len, 0)
        guard sentLen == len else {
            throw SocketsError(.sendFailedToSendAllBytes)
        }
    }

    public func write(buffer buf: ByteBuffer) throws {
        let len = buf.remaining
        let sentLen = libc.send(descriptor.raw, buf.getUnsafeMutablePointer(), len, 0)
        guard sentLen == len else {
            throw SocketsError(.sendFailedToSendAllBytes)
        }
    }
    
    public func flush() throws {
        // no need to flush
    }
}
