//
//  DataDecoder.swift
//
//
//  Created by Nicholas Mata on 6/13/22.
//

import Foundation

/// Decodes Data to an indicated type.
public protocol DataDecoder {
  /// Decodes an instance of the indicated type.
  func decode<T>(_ type: T.Type, from: Data) throws -> T where T: Decodable
}

extension JSONDecoder: DataDecoder {}
