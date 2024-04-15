//
//  OAuthTokenManagedProvider.swift
//
//
//  Created by Nicholas Mata on 4/15/24.
//

import Foundation

public protocol OAuthTokenManagedProvider: OAuthProvider {
  /// The token manager that will be used to store and retrieve the access and refresh token
  var tokenManager: TokenManager { get set }

  /// Refresh the token provided
  /// - Parameter completion: A function to call when the token is refreshed or fails to refresh.
  func refreshToken(completion: @escaping (Result<String, Error>) -> Void)

  /// Attach the token to the request. The default implementation will add token to "Authorization" header as Bearer token.
  /// - Parameters:
  ///   - token: The token to add to the request
  ///   - request: The request to add the token too
  /// - Returns: The new request with the token attached to it
  func attach(token: String, to request: URLRequest) -> URLRequest
}

public extension OAuthTokenManagedProvider where Self: AnyObject {
  var tokenState: TokenState {
    guard let accessToken = tokenManager.accessToken, !accessToken.isExpired() else {
      guard let refreshToken = tokenManager.refreshToken, !refreshToken.isExpired() else {
        return .missing
      }
      return .expired
    }
    return .valid(token: accessToken.token)
  }
}
