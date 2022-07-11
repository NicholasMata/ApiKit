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
//    static let service = "token"
//    static let account = "google.com"
//    public var token: String? {
//        set(newValue) {
//            KeychainHelper.standard.save(token?.data(using: .utf8),
//                                         service: DefaultGoogleAuthProvider.service,
//                                         account: DefaultGoogleAuthProvider.account)
//        }
//        get {
//            let data = KeychainHelper.standard.read(service: DefaultGoogleAuthProvider.service,
//                                                    account: DefaultGoogleAuthProvider.account)
//            guard let data = data else {
//                return nil
//            }
//            return String(data: data, encoding: .utf8)
//        }
//    }

  public var token: String? {
    return GIDSignIn.sharedInstance.currentUser?.authentication.accessToken
  }

  private var googleSignIn = GIDSignIn.sharedInstance

  public enum GoogleAuthError: Error {
    case unknown
  }

  public func hasPreviousSignIn() -> Bool {
    return googleSignIn.hasPreviousSignIn()
  }

  public func restorePreviousSignIn(completion: @escaping (Result<String, Error>) -> Void) {
    googleSignIn.restorePreviousSignIn { user, error in
      guard error == nil else {
        completion(.failure(error!))
        return
      }

      guard let user = user else {
        completion(.failure(GoogleAuthError.unknown))
        return
      }
//            self.token = user.authentication.accessToken
      completion(.success(user.authentication.accessToken))
    }
  }
}
