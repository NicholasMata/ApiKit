//
//  TokenState.swift
//
//
//  Created by Nicholas Mata on 4/14/24.
//

import Foundation

public enum TokenState: Equatable {
  /// Indicates the token is valid
  case valid(token: String)
  /// Indicates the token is expired, but can be renewed.
  case expired
  /// Indicates the token is no longer and has no way of being renewed.
  case missing
}
