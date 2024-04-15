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
  open var googleSignIn = GIDSignIn.sharedInstance

  public init() {}
  
  public var tokenState: TokenState {
    get {
      guard let currentUser = googleSignIn.currentUser else {
        return TokenState.missing
      }
      let expiration = currentUser.authentication.accessTokenExpirationDate
      guard expiration <= Date() else {
        return TokenState.expired
      }
      return TokenState.valid(token: token(for: currentUser))
    }
  }

  open func token(for user: GIDGoogleUser) -> String {
    return user.authentication.accessToken
  }


  public func refreshToken(completion: @escaping (Result<String, any Error>) -> Void) {
    googleSignIn.restorePreviousSignIn { user, error in
      guard error == nil else {
        completion(.failure(error!))
        return
      }

      guard let user = user else {
        completion(.failure(GoogleAuthError.unknown))
        return
      }

      let token = self.token(for: user)
      completion(.success(token))
    }
  }
}

public enum GoogleAuthError: Error {
  case unknown
}
