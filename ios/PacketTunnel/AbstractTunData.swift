//
//  AbstractTunData.swift
//  PacketTunnel
//
//  Created by Emils on 02/06/2023.
//  Copyright © 2023 Mullvad VPN AB. All rights reserved.
//

import Foundation



class DataWrapper {
    let data: Data
    init(_ data: Data) {
        self.data = data
    }
}


class DataArray {
    var arr: [Data]
    
    init(arr: [Data]) {
        self.arr = arr
    }
    
    init() {
        self.arr = []
    }
    
    func push(_ data: Data) {
        self.arr.append(data)
    }
}

typealias IterationCallback = (UnsafeMutableRawPointer, uintptr_t, UnsafeMutableRawPointer) -> Void;

@_cdecl("swift_data_array_iterate")
func dataArrayIterate(ptr: UnsafeMutableRawPointer, context: UnsafeMutableRawPointer, iterationCallback: IterationCallback) {
    let dataPtr = Unmanaged<DataArray>.fromOpaque(ptr)
    let dataArray = dataPtr.takeUnretainedValue()
    
    for var data in dataArray.arr {
        let size = UInt(data.count)
        data.withUnsafeMutableBytes { dataPtr in
            iterationCallback(dataPtr, size, context)
        }
    }
}

@_cdecl("swift_data_array_drop")
func dataArrayDrop(ptr: UnsafeRawPointer) {
    let data = Unmanaged<DataArray>.fromOpaque(ptr)
    data.release()
}

@_cdecl("swift_data_drop")
func dataDrop(ptr: UnsafeRawPointer) {
    let data = Unmanaged<DataWrapper>.fromOpaque(ptr)
    data.release()
}

@_cdecl("swift_data_create")
func dataCreate(size: UInt) -> SwiftData {
    let data = DataWrapper(Data(repeating: 0, count: Int(size)))
    let dataPtr = (data.data as NSData).bytes.assumingMemoryBound(to: UInt8.self)
    let mutatingDataPtr = UnsafeMutablePointer(mutating: dataPtr)
    let wrapperPtr = Unmanaged<DataWrapper>.passRetained(data).toOpaque()
    
    return SwiftData(swift_data_ptr: wrapperPtr, bytes_ptr: mutatingDataPtr, size: size)
}


