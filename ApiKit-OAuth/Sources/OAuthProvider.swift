//
//  OAuthProvider.swift
//
//
//  Created by Nicholas Mata on 6/14/22.
//

import Foundation

/// An OAuth provider that manages access token.
public protocol OAuthProvider {
  
  /// Get the current state of the access token.
  var tokenState: TokenState { get }
  
  /// Refresh the token provided
  /// - Parameter completion: A function to call when the token is refreshed or fails to refresh.
  func refreshToken(completion: @escaping (Result<String, Error>)-> Void)
  
  /// Attach the token to the request. The default implementation will add token to "Authorization" header as Bearer token.
  /// - Parameters:
  ///   - token: The token to add to the request
  ///   - request: The request to add the token too
  /// - Returns: The new request with the token attached to it
  func attach(token: String, to request: URLRequest) -> URLRequest
}

public extension OAuthProvider where Self: AnyObject {
  func attach(token: String, to request: URLRequest) -> URLRequest {
    let bearerToken = "Bearer \(token)"
    var request = request
    if request.allHTTPHeaderFields != nil {
      request.allHTTPHeaderFields?.updateValue(bearerToken, forKey: "Authorization")
    } else {
      request.allHTTPHeaderFields = ["Authorization": bearerToken]
    }
    return request
  }
}
