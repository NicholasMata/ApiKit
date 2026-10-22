//
//  DefaultGoogleAuthProvider.swift
//
//
//  Created by Nicholas Mata on 6/13/22.
//

import ApiKit
import ApiKit_OAuth
import Foundation
import GoogleSignIn

/// A default implementation of GoogleSignIn.
open class DefaultGoogleAuthProvider: OAuthProvider {
  private var clientOverride: GoogleSignInClient?
  private var client: GoogleSignInClient { clientOverride ?? googleSignIn }
  open var googleSignIn = GIDSignIn.sharedInstance

  public init() {}

  init(client: GoogleSignInClient) {
    clientOverride = client
  }

  public var tokenState: TokenState {
      guard let currentUser = client.currentUser else {
        return TokenState.missing
      }
      let expiration = currentUser.authentication.accessTokenExpirationDate
      guard Date() <= expiration, let token = token(for: currentUser) else {
        return TokenState.expired
      }
      return TokenState.valid(token: token)
    }

  open func token(for user: GIDGoogleUser) -> String? {
    return user.authentication.accessToken
  }

  public func refreshToken(completion: @escaping (Result<String, any Error>) -> Void) {
    client.restorePreviousSignIn { user, error in
      guard error == nil else {
        completion(.failure(error!))
        return
      }

      guard let user = user else {
        completion(.failure(GoogleAuthError.unknown))
        return
      }

      guard let token = self.token(for: user) else {
        completion(.failure(OAuthError.noToken))
        return
      }

      completion(.success(token))
    }
  }
}

public enum GoogleAuthError: Error {
  case unknown
}

/// Allows offline tests without changing the public provider or restoration behavior.
protocol GoogleSignInClient {
  var currentUser: GIDGoogleUser? { get }
  func restorePreviousSignIn(callback: GIDSignInCallback?)
}

extension GIDSignIn: GoogleSignInClient {}
