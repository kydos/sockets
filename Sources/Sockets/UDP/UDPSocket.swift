import libc
import Snio

public class UDPInternetSocket: InternetSocket {

    public let descriptor: Descriptor
    public let config: Config
    public let address: ResolvedInternetAddress
    public private(set) var isClosed = false

    public required init(descriptor: Descriptor?, config: Config, address: ResolvedInternetAddress) throws {

        if let descriptor = descriptor {
            self.descriptor = descriptor
        } else {
            self.descriptor = try Descriptor(config)
        }
        self.config = config
        self.address = address
    }

    public convenience init(address: InternetAddress) throws {
        var conf: Config = .UDP(addressFamily: address.addressFamily)
        let resolved = try address.resolve(with: &conf)
        try self.init(descriptor: nil, config: conf, address: resolved)
    }

    deinit {
        try? self.close()
    }

    
    public func recvfrom(_ buf: ByteBuffer) throws -> ResolvedInternetAddress {
        if isClosed { throw SocketsError(.socketIsClosed) }
        let pos = buf.position
        let lim = buf.limit
        let len = lim - pos
        let rawBuf = buf.getUnsafeMutablePointer()
        let flags: Int32 = 0 //FIXME: allow setting flags with a Swift enum
        
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let addr = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
        let addrSockAddr = UnsafeMutablePointer<sockaddr>(OpaquePointer(addr))
        
        let receivedBytes = libc.recvfrom(
            descriptor.raw,
            rawBuf,
            len,
            flags,
            addrSockAddr,
            &length
        )
        guard receivedBytes > -1 else {
            addr.deallocate(capacity: 1)
            throw SocketsError(.readFailed)
        }
        buf.position = buf.position + receivedBytes
        
        return ResolvedInternetAddress(raw: addr)
    }
    
    public func recvfrom(maxBytes: Int = BufferCapacity) throws -> (data: [UInt8], sender: ResolvedInternetAddress) {
        if isClosed { throw SocketsError(.socketIsClosed) }
        let data = Buffer(capacity: maxBytes)
        let flags: Int32 = 0 //FIXME: allow setting flags with a Swift enum

        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let addr = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
        let addrSockAddr = UnsafeMutablePointer<sockaddr>(OpaquePointer(addr))

        let receivedBytes = libc.recvfrom(
            descriptor.raw,
            data.pointer,
            data.capacity,
            flags,
            addrSockAddr,
            &length
        )
        guard receivedBytes > -1 else {
            addr.deallocate(capacity: 1)
            throw SocketsError(.readFailed)
        }

        let clientAddress = ResolvedInternetAddress(raw: addr)

        let finalBytes = data.bytes[0..<receivedBytes]
        let out = Array(finalBytes)
        return (data: out, sender: clientAddress)
    }

    private func createMembershipRequest(_ ip: String, _ ifaddr: String) -> ip_mreq {
        let group = inet_addr(ip)
        let iface = inet_addr(ifaddr)
        var imr =  ip_mreq()
        imr.imr_multiaddr.s_addr = group;
        imr.imr_interface.s_addr = iface
        return imr
    }
    
    public func join(group mcastAddr: String, iface ifname: String) throws {
        let imr = self.createMembershipRequest(mcastAddr, ifname)
        try self.descriptor.setOption(level: Int32(IPPROTO_IP), name: IP_ADD_MEMBERSHIP, value: imr)
    
    }
    
    public func leave(group mcastAddr: String, iface ifname: String) throws {
        let imr = self.createMembershipRequest(mcastAddr, ifname)
        try self.descriptor.setOption(level: Int32(IPPROTO_IP), name: IP_ADD_MEMBERSHIP, value: imr)
    
    }
    
    public func sendto(data: [UInt8], address: ResolvedInternetAddress? = nil) throws {
        if isClosed { throw SocketsError(.socketIsClosed) }
        let len = data.count
        let flags: Int32 = 0 //FIXME: allow setting flags with a Swift enum
        let destination = address ?? self.address

        let sentLen = libc.sendto(
            descriptor.raw,
            data,
            len,
            flags,
            destination.raw,
            destination.rawLen
        )
        guard sentLen == len else { throw SocketsError(.sendFailedToSendAllBytes) }
    }

    

    public func sendto(_ buf: ByteBuffer, address: ResolvedInternetAddress? = nil) throws {
        if isClosed { throw SocketsError(.socketIsClosed) }
        let len = buf.limit - buf.position
        let flags: Int32 = 0 //FIXME: allow setting flags with a Swift enum
        let destination = address ?? self.address
        
        let sentLen = libc.sendto(
            descriptor.raw,
            buf.getUnsafeMutablePointer(),
            len,
            flags,
            destination.raw,
            destination.rawLen
        )
        guard sentLen == len else { throw SocketsError(.sendFailedToSendAllBytes) }
        buf.position = buf.limit
    }
    

    

    public func close() throws {
        if isClosed { return }
        isClosed = true
        if libc.close(descriptor.raw) != 0 {
            throw SocketsError(.closeSocketFailed)
        }
    }
}
