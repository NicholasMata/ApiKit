//
//  Token.swift
//
//
//  Created by Nicholas Mata on 4/14/24.
//

import Foundation

public struct Token {
    /// The number of seconds to pad expiresOn
    static let expirationPadding: Double = 60

    /// The token value
    public var token: String
    /// The number of seconds from retrieval to expiration
    public var expiresIn: Int
    /// The date and time the token was retrieved.
    public var retrievedOn: Date
    /// The date and time the token will expire
    public var expiresOn: Date {
        return retrievedOn.addingTimeInterval(Double(expiresIn))
    }

    /// Whether the token is valid.
    public func isValid() -> Bool {
        return Date() <= expiresOn.addingTimeInterval(-Token.expirationPadding)
    }

    public func isExpired() -> Bool {
      return !isValid()
    }
}
