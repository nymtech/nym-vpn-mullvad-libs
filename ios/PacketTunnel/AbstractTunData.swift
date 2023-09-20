//
//  AbstractTunData.swift
//  PacketTunnel
//
//  Created by Emils on 02/06/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation


class DataArray {
    public var arr: [Data]
    
    init(_ arr: [Data]) {
        self.arr = arr
    }
    
    init() {
        arr = []
    }
    
    init(data arr: [Data]) {
        self.arr = arr
    }
    
    func append(_ data: Data) {
        arr.append(data)
    }
    
    func len() -> UInt64 {
        UInt64(arr.count)
    }
    
    static func fromRawPtr(_ ptr: UnsafeMutableRawPointer) -> DataArray {
        let arr = Unmanaged<DataArray>.fromOpaque(ptr).takeUnretainedValue()
        return arr
    }
    
    static func fromSwiftData(_ swiftData: SwiftDataArray) -> DataArray {
        let arr = Unmanaged<DataArray>.fromOpaque(swiftData.array_ptr).takeUnretainedValue()
        return arr
    }
    
    func toRaw() -> SwiftDataArray {
        let ptr = Unmanaged<DataArray>.passRetained(self).toOpaque()
        return SwiftDataArray(array_ptr: ptr)
    }
    
    
    static func runTest() -> (DataArray, UInt8){
        guard let wrappedArrayPtr = swift_data_array_test() else { return (DataArray([]), 0)}
        let array = Unmanaged<DataArray>.fromOpaque(wrappedArrayPtr).takeRetainedValue()
        var sum = UInt8(0)
        for arr in array.arr {
            for byte in arr {
                sum += byte
            }
        }
        return (array, sum)
    }
}

@_cdecl("swift_data_array_create")
func dataArrayCreate() -> UnsafeMutableRawPointer {
    let arr = DataArray([])
    return Unmanaged<DataArray>.passRetained(arr).toOpaque()
}

@_cdecl("swift_data_array_append")
func dataArrayAppend(ptr: UnsafeMutableRawPointer, dataPtr: UnsafeRawPointer, dataLen: UInt ) {
    let arr = DataArray.fromRawPtr(ptr)
    let data = Data(bytes: dataPtr, count: Int(dataLen))
    arr.append(data)
}

@_cdecl("swift_data_array_drop")
func dataArrayDrop(ptr: UnsafeRawPointer) {
    let data = Unmanaged<DataArray>.fromOpaque(ptr)
    data.release()
}

@_cdecl("swift_data_array_len")
func dataArrayLen(ptr: UnsafeMutableRawPointer) -> UInt64 {
    let arr = DataArray.fromRawPtr(ptr)
    return arr.len()
}

@_cdecl("swift_data_array_get")
func dataArrayGet(ptr: UnsafeMutableRawPointer, idx: UInt64) -> SwiftData {
    let dataArray = DataArray.fromRawPtr(ptr)
    let data = dataArray.arr[Int(idx)]
    let dataPtr = (data as NSData).bytes.assumingMemoryBound(to: UInt8.self)
    let mutatingDataPtr = UnsafeMutablePointer(mutating: dataPtr)
    return SwiftData(ptr: mutatingDataPtr, len: UInt(data.count))
}

