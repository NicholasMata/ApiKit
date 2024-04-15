//
//  OIDCResponse.swift
//
//
//  Created by Nicholas Mata on 4/15/24.
//

import Foundation

public class OIDCTokenResponse: Codable {
    public var accessToken: String
    public var tokenType: String
    public var expiresIn: Int
    public var refreshToken: String?
    public var refreshTokenExpiresIn: Int?
    public var idToken: String?
}
