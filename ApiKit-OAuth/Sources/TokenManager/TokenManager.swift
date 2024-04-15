//
//  TokenManager.swift
//
//
//  Created by Nicholas Mata on 4/14/24.
//

import Foundation

public protocol TokenManager {
    var refreshToken: Token? { get set }
    var accessToken: Token? { get set }

    func decode(from response: Data)
    func clear()
}
