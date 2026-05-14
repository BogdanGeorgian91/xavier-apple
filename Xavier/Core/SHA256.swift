//
//  SHA256.swift
//  Xavier
//
//

import Foundation
import CommonCrypto

extension Data {
    public var SHA256:Data {
        var dataBytes = self.bytes
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(&dataBytes, CC_LONG(self.count), &hash)
        
        return Data(bytes: hash)
    }
    
    public var bytes:[UInt8] {
        return self.withUnsafeBytes {
            [UInt8](UnsafeBufferPointer(start: $0, count: self.count))
        }
    }
    
    public var hex:String {
        let bytes = self.withUnsafeBytes {
            [UInt8](UnsafeBufferPointer(start: $0, count: self.count))
        }
        
        var hexString = ""
        for i in 0..<self.count {
            hexString += String(format: "%02x", bytes[i])
        }
        return hexString
    }
}

extension String {
    public var SHA256:Data {
        return Data(bytes: [UInt8](self.utf8)).SHA256
    }
}
