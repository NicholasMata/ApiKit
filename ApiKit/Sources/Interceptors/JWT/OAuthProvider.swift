//
//  OAuthProvider.swift
//
//
//  Created by Nicholas Mata on 6/14/22.
//

import Foundation

/// An OAuth provider that manages access token.
public protocol OAuthProvider {
  /// Retrieves the current access/id token.
  var token: String? { get }
  /// Checks if there is a previously authenticated user saved preferably stored in Keychain.
  /// - Returns: A boolean indicating if there was a previously authenticated user.
  func hasPreviousSignIn() -> Bool

  /// Restores a previous sign in either using a refresh token or some other method.
  /// - Parameter completion: Called either on failure or success to renew token,.
  func restorePreviousSignIn(completion: @escaping (Result<String, Error>) -> Void)

  /// Modifies the request. The default implementation is to add "Authorization" header as Bearer token
  /// - Parameters:
  ///   - request: The request to modify
  ///   - token: A token that should be add to request.
  /// - Returns: The request modified to have the token.
  func modify(request: URLRequest, token: String) -> URLRequest
}

public extension OAuthProvider where Self: AnyObject {
  func modify(request: URLRequest, token: String) -> URLRequest {
    let bearerToken = "Bearer \(token)"
    var request = request
    if var headers = request.allHTTPHeaderFields {
      headers.updateValue(bearerToken, forKey: "Authorization")
    } else {
      request.allHTTPHeaderFields = ["Authorization": bearerToken]
    }
    return request
  }
}
