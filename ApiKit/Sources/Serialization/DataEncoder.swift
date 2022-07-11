//
//  DataEncoder.swift
//
//
//  Created by Nicholas Mata on 6/14/22.
//

import Foundation

/// Encodes indicated type to Data.
public protocol DataEncoder {
  // Encodes an instance to data.
  func encode<T>(_ value: T) throws -> Data where T: Encodable
}

extension JSONEncoder: DataEncoder {}

extension URLEncodedFormEncoder: DataEncoder {}
