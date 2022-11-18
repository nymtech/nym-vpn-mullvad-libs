//
//  RouteResolution.swift
//  DNSProxy
//
//  Created by pronebird on 18/11/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import Network

struct RouteResolution {
    var destination: IPAddress
    var gateway: IPAddress?
    var netmask: String?
    var interfaceName: String
    var interfaceIndex: UInt16
}

private var sequenceCounter: Int32 = 0
private let sequenceLock = NSLock()

private func getNextSequenceIdentifier() -> Int32 {
    sequenceLock.lock()
    defer { sequenceLock.unlock() }
    let (partialValue, overflow) = sequenceCounter.addingReportingOverflow(1)
    sequenceCounter = overflow ? 1 : partialValue

    return sequenceCounter
}

func resolveRoute(to ipAddress: IPAddress) throws -> RouteResolution {
    let pid = ProcessInfo.processInfo.processIdentifier
    let seq = getNextSequenceIdentifier()

    var ss = sockaddr_storage()
    ss.ss_len = UInt8(MemoryLayout<sockaddr_in>.size)

    if let ipv4Address = ipAddress as? IPv4Address {
        ss.ss_family = sa_family_t(AF_INET)
        ss.ss_len = UInt8(MemoryLayout<sockaddr_in>.size)

        withUnsafeMutableBytes(of: &ss) { buffer in
            buffer.withMemoryRebound(to: sockaddr_in.self) { sin in
                sin.baseAddress?.pointee.sin_addr = ipv4Address.rawValue.withUnsafeBytes { data in
                    return data.load(as: in_addr.self)
                }
            }
        }
    } else if let ipv6Address = ipAddress as? IPv6Address {
        ss.ss_family = sa_family_t(AF_INET6)
        ss.ss_len = UInt8(MemoryLayout<sockaddr_in6>.size)

        withUnsafeMutableBytes(of: &ss) { buffer in
            buffer.withMemoryRebound(to: sockaddr_in6.self) { sin in
                sin.baseAddress?.pointee.sin6_addr = ipv6Address.rawValue.withUnsafeBytes { data in
                    return data.load(as: in6_addr.self)
                }
            }
        }
    } else {
        throw RouteResolutionError.unsupportedIPAddress
    }

    var msg = rt_msghdr()
    msg.rtm_msglen = UInt16(MemoryLayout<rt_msghdr>.size + MemoryLayout<sockaddr_storage>.size)
    msg.rtm_version = UInt8(RTM_VERSION)
    msg.rtm_type = UInt8(RTM_GET)
    msg.rtm_addrs = RTA_DST | RTA_GATEWAY | RTA_IFP
    msg.rtm_flags = RTF_UP | RTF_GATEWAY | RTF_STATIC
    msg.rtm_pid = pid
    msg.rtm_seq = seq

    let sock = socket(PF_ROUTE, SOCK_RAW, 0)
    guard sock >= 0 else {
        throw RouteResolutionError.openSocket(.errno)
    }

    defer { close(sock) }

    var data = [UInt8]()

    withUnsafeBytes(of: &msg) { buffer in
        data.append(contentsOf: buffer)
    }
    withUnsafeBytes(of: &ss) { buffer in
        data.append(contentsOf: buffer)
    }

    let bytesWritten = data.withUnsafeBytes { buffer in
        return write(sock, buffer.baseAddress!, Int(msg.rtm_msglen))
    }

    guard bytesWritten > 0 else {
        throw RouteResolutionError.writeError(.errno)
    }

    var replyBuffer = [UInt8](repeating: 0, count: 4096)

    while true {
        let bytesRead = read(sock, &replyBuffer, replyBuffer.count)

        guard bytesRead > 0 else {
            throw RouteResolutionError.readError(.errno)
        }

        guard bytesRead >= MemoryLayout<rt_msghdr>.size else {
            throw RouteResolutionError.invalidMessageLength
        }

        let replyMsg = replyBuffer.withUnsafeBytes { bufferPointer in
            return bufferPointer.load(as: rt_msghdr.self)
        }

        guard replyMsg.rtm_version == RTM_VERSION else {
            throw RouteResolutionError.invalidVersion
        }

        guard replyMsg.rtm_pid == pid, replyMsg.rtm_seq == seq else {
            continue
        }

        guard replyMsg.rtm_errno == 0 else {
            throw RouteResolutionError.messageWithError(replyMsg.rtm_errno)
        }

        var destination: UnsafeRawPointer?
        var gateway: UnsafeRawPointer?
        var mask: UnsafeRawPointer?
        var ifp: UnsafeRawPointer?

        guard replyMsg.rtm_addrs > 0 else {
            throw RouteResolutionError.noAddresses
        }

        replyBuffer.withUnsafeBytes { buffer in
            var payloadPointer = buffer.baseAddress!.advanced(by: MemoryLayout<rt_msghdr>.size)

            var i: Int32 = 1
            while i > 0 {
                defer { i <<= 1 }

                guard (i & replyMsg.rtm_addrs) != 0 else { continue }

                let sa = payloadPointer.load(as: sockaddr.self)

                switch i {
                case RTA_DST:
                    destination = payloadPointer

                case RTA_GATEWAY:
                    gateway = payloadPointer

                case RTA_NETMASK:
                    mask = payloadPointer

                case RTA_IFP:
                    if sa.sa_family == AF_LINK {
                        let sdl = payloadPointer.assumingMemoryBound(to: sockaddr_dl.self)
                        if sdl.pointee.sdl_nlen > 0 {
                            ifp = payloadPointer
                        }
                    }

                default:
                    break
                }

                payloadPointer = payloadPointer
                    .advanced(by: Int(sa.sa_len))
                    .alignedUp(for: UInt32.self)
            }
        }

        var result = RouteResolution(
            destination: IPv4Address.any,
            interfaceName: "",
            interfaceIndex: 0
        )

        if let destination = destination {
            do {
                result.destination = try parseIPAddress(from: destination)
            } catch {
                throw RouteResolutionError.parseDestinationIP(error as! ParseIPAddressError)
            }
        }

        if let gateway = gateway, (replyMsg.rtm_flags & RTF_GATEWAY) != 0 {
            do {
                result.gateway = try parseIPAddress(from: gateway)
            } catch {
                throw RouteResolutionError.parseGatewayIP(error as! ParseIPAddressError)
            }
        }

        if let mask = mask, let destination = destination {
            let sf = destination.assumingMemoryBound(to: sockaddr.self).pointee.sa_family

            do {
                result.netmask = try parseNetmask(from: mask, family: sf)
            } catch {
                throw RouteResolutionError.parseNetmask(error as! ParseNetmaskError)
            }
        }

        if let ifp = ifp {
            let sdl = ifp.assumingMemoryBound(to: sockaddr_dl.self).pointee
            if sdl.sdl_nlen > 0 {
                let name = withUnsafeBytes(of: sdl.sdl_data) { buffer in
                    return String(bytes: buffer[..<Int(sdl.sdl_nlen)], encoding: .ascii)
                }

                result.interfaceName = name ?? ""
            }

            result.interfaceIndex = sdl.sdl_index
        }

        return result
    }
}

func parseIPAddress(from sockaddrPointer: UnsafeRawPointer) throws -> IPAddress {
    let sa = sockaddrPointer.assumingMemoryBound(to: sockaddr.self).pointee
    switch Int32(sa.sa_family) {
    case AF_INET:
        let sa = sockaddrPointer.load(as: sockaddr_in.self)
        let ipv4Address = withUnsafeBytes(of: sa.sin_addr) { buffer in
            return IPv4Address(Data(buffer))
        }

        if let ipv4Address = ipv4Address {
            return ipv4Address
        } else {
            throw ParseIPAddressError(sa: sa)
        }

    case AF_INET6:
        let sa6 = sockaddrPointer.load(as: sockaddr_in6.self)
        let ipv6Address = withUnsafeBytes(of: sa6.sin6_addr) { buffer in
            return IPv6Address(Data(buffer))
        }
        if let ipv6Address = ipv6Address {
            return ipv6Address
        } else {
            throw ParseIPAddressError(sa6: sa6)
        }

    default:
        throw ParseIPAddressError(sa: sa)
    }
}

func parseNetmask(from sockaddrPointer: UnsafeRawPointer, family: sa_family_t) throws -> String {
    let sf = Int32(family)
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))

    switch sf {
    case AF_INET:
        return try sockaddrPointer.withMemoryRebound(
            to: sockaddr_in.self,
            capacity: 1
        ) { pointer throws -> String in
            if let addrPointer = pointer.pointer(to: \.sin_addr),
               let cString = inet_ntop(sf, addrPointer, &buffer, socklen_t(buffer.count))
            {
                return String(cString: cString)
            } else {
                throw ParseNetmaskError(sa: pointer.pointee, family: family)
            }
        }

    case AF_INET6:
        return try sockaddrPointer.withMemoryRebound(
            to: sockaddr_in6.self,
            capacity: 1
        ) { pointer throws -> String in
            if let addrPointer = pointer.pointer(to: \.sin6_addr),
               let cString = inet_ntop(sf, addrPointer, &buffer, socklen_t(buffer.count))
            {
                return String(cString: cString)
            } else {
                throw ParseNetmaskError(sa6: pointer.pointee, family: family)
            }
        }

    default:
        throw ParseNetmaskError(sa: sockaddrPointer.load(as: sockaddr.self), family: family)
    }
}
