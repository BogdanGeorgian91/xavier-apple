//
//  UniqueID.swift
//  Xavier
//
//

import Foundation
import CommonCrypto

public func uniqueIdentifier(of attrs:String...) -> String {
    var input = ""
    attrs.forEach {
        input += $0.SHA256.hex
    }
    
    return String(input.SHA256.hex.suffix(16))
}
