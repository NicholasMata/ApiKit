//
//  DefaultGoogleAuthProvider.swift
//
//
//  Created by Nicholas Mata on 6/13/22.
//

import ApiKit
import Foundation
import GoogleSignIn

/// A default implementation of GoogleSignIn.
open class DefaultGoogleAuthProvider: OAuthProvider {
  open var token: String? {
    return self.token(for: GIDSignIn.sharedInstance.currentUser)
  }

  open var googleSignIn = GIDSignIn.sharedInstance

  public init() {}

  open func hasPreviousSignIn() -> Bool {
    return googleSignIn.hasPreviousSignIn()
  }

  open func restorePreviousSignIn(completion: @escaping (Result<String, Error>) -> Void) {
    googleSignIn.restorePreviousSignIn { user, error in
      guard error == nil else {
        completion(.failure(error!))
        return
      }

      guard let user = user, let token = self.token(for: user) else {
        completion(.failure(GoogleAuthError.unknown))
        return
      }
      completion(.success(token))
    }
  }

  open func token(for user: GIDGoogleUser?) -> String? {
    return user?.authentication.accessToken
  }
}

public enum GoogleAuthError: Error {
  case unknown
}
