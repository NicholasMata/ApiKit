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
open class DefaultGoogleAuthProvider: OAuthProvider, OAuthSessionEvents {
  private let events = OAuthSessionEventPublisher()
  private let lock = NSRecursiveLock()
  private var sessionId = UUID()
  private var pending: [UUID: (session: UUID, user: GIDGoogleUser, completion: (Result<String, Error>) -> Void)] = [:]
  private var clientOverride: GoogleOAuthClient?
  private var client: GoogleOAuthClient {
    clientOverride ?? googleSignIn
  }

  open var googleSignIn = GIDSignIn.sharedInstance

  public init() {}

  init(client: GoogleOAuthClient) {
    clientOverride = client
  }

  public func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription {
    events.subscribe(event, handler)
  }

  public func endSession() {
    lock.lock()
    sessionId = UUID()
    let completions = pending.values.map { $0.completion }
    pending.removeAll()
    client.signOut()
    lock.unlock()
    events.send(.sessionEnded)
    for completion in completions {
      completion(.failure(OAuthError.sessionEnded))
    }
  }

  public var tokenState: TokenState {
    lock.lock()
    defer { lock.unlock() }
    let session = sessionId
    guard let currentUser = client.currentUser else {
      return TokenState.missing
    }
    let expiration = currentUser.authentication.accessTokenExpirationDate
    guard Date() <= expiration, let token = token(for: currentUser) else {
      return TokenState.expired
    }
    guard sessionId == session, client.currentUser === currentUser else { return .missing }
    return TokenState.valid(token: token)
  }

  open func token(for user: GIDGoogleUser) -> String? {
    return user.authentication.accessToken
  }

  public func refreshToken(completion: @escaping (Result<String, any Error>) -> Void) {
    lock.lock()
    let client = client
    guard let user = client.currentUser else {
      lock.unlock()
      completion(.failure(OAuthError.noToken))
      return
    }
    let id = UUID()
    pending[id] = (sessionId, user, completion)
    lock.unlock()
    client.refreshTokens(for: user) { [weak self] error in
      self?.finishRefresh(id: id, client: client, error: error)
    }
  }

  private func finishRefresh(id: UUID, client: GoogleOAuthClient, error: Error?) {
    lock.lock()
    guard let attempt = pending.removeValue(forKey: id) else {
      lock.unlock()
      return
    }
    let result: Result<String, Error>
    if sessionId != attempt.session || client.currentUser !== attempt.user {
      result = .failure(OAuthError.sessionEnded)
    } else if let error = error {
      result = .failure(error)
    } else if let token = token(for: attempt.user) {
      result = .success(token)
    } else {
      result = .failure(OAuthError.noToken)
    }
    lock.unlock()
    // Delivery is claimed separately, allowing a sign-out during token extraction
    // to invalidate the result without invoking application callbacks under a lock.
    lock.lock()
    let current = sessionId == attempt.session && client.currentUser === attempt.user
    lock.unlock()
    attempt.completion(current ? result : .failure(OAuthError.sessionEnded))
  }
}

/// Keeps SDK interaction replaceable in tests without changing the public API.
protocol GoogleOAuthClient: AnyObject {
  var currentUser: GIDGoogleUser? { get }
  func refreshTokens(for user: GIDGoogleUser, completion: @escaping (Error?) -> Void)
  func signOut()
}

extension GIDSignIn: GoogleOAuthClient {
  func refreshTokens(for user: GIDGoogleUser, completion: @escaping (Error?) -> Void) {
    // Unlike restoration, this updates only the existing authentication object;
    // it does not run GIDSignIn's save-auth/current-user restoration flow.
    user.authentication.do { _, error in completion(error) }
  }
}

public enum GoogleAuthError: Error {
  case unknown
}
