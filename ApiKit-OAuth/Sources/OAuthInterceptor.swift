//
//  OAuthInterceptor.swift
//
//
//  Created by Nicholas Mata on 6/14/22.
//

import ApiKit
import Foundation

public enum OAuthError: Error {
  case failedToRenew
  case noToken
  /// A refresh belonged to an authentication session that has ended.
  case sessionEnded
}

/// Used to add OAuth access token to request for authentication / authorization.
open class OAuthInterceptor: ApiInterceptor {
  private let queue = DispatchQueue(label: "ApiKit.OAuthInterceptor")
  private let sessionLock = NSRecursiveLock()
  private var sessionId = UUID()
  private var subscriptions: [OAuthSubscription] = []
  private var refreshId: UUID?
  private var pendingRequests: [(request: URLRequest, completion: (URLRequest?) -> Void)] = []
  /// A callack that will get called on the DispatchQueue.main indicating the user could not be signed in silently.
  public var onFailedToRenew: ((Error?) -> Void)?
  private var provider: OAuthProvider

  private var workItem: DispatchWorkItem?

  /// Initializes a new instance of OAuthInterceptor.
  /// - Parameters:
  ///   - provider: The oauth provider that is responsible for managing token.
  ///   - onFailedToRenew: A callack that will get called on the DispatchQueue.main indicating the user could not be signed in silently.
  public init(provider: OAuthProvider, onFailedToRenew: ((Error?) -> Void)? = nil) {
    self.provider = provider
    self.onFailedToRenew = onFailedToRenew
    if let events = provider as? OAuthSessionEvents {
      for event in [OAuthSessionEvent.signOut, .sessionStarted] {
        subscriptions.append(events.subscribe(event) { [weak self] in
          self?.sessionDidEnd()
        })
      }
    }
  }

  private func sessionDidEnd() {
    sessionLock.lock()
    sessionId = UUID()
    queue.async {
      self.refreshId = nil
      self.workItem?.cancel()
      self.workItem = nil
      let requests = self.pendingRequests
      self.pendingRequests.removeAll()
      for pending in requests {
        pending.completion(nil)
      }
    }
    sessionLock.unlock()
  }

  private func failedToRenew(with err: Error?) {
    workItem?.cancel()
    let id = sessionId
    let workItem = DispatchWorkItem(block: { [weak self] in
      guard let self = self else { return }
      self.sessionLock.lock()
      defer { self.sessionLock.unlock() }
      guard self.sessionId == id else { return }
      self.onFailedToRenew?(err)
    })
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    self.workItem = workItem
  }

  public func api(_: Api,
                  modifyRequest request: URLRequest,
                  withId _: UUID,
                  onNewRequest: @escaping (URLRequest?) -> Void)
  {
    sessionLock.lock()
    let id = sessionId
    queue.async { self.prepare(request, sessionId: id, completion: onNewRequest) }
    sessionLock.unlock()
  }

  private func prepare(_ request: URLRequest, sessionId: UUID, completion: @escaping (URLRequest?) -> Void) {
    // Read the provider outside the session lock: providers can publish events
    // while coordinating their own credential storage.
    let state = provider.tokenState
    sessionLock.lock()
    guard self.sessionId == sessionId else {
      sessionLock.unlock()
      completion(nil)
      return
    }
    if refreshId != nil {
      pendingRequests.append((request, completion))
      sessionLock.unlock()
      return
    }

    switch state {
    case let .valid(token):
      let request = provider.attach(token: token, to: request)
      completion(self.sessionId == sessionId ? request : nil)
      sessionLock.unlock()
    case .missing:
      completion(nil)
      if self.sessionId == sessionId {
        failedToRenew(with: OAuthError.noToken)
      }
      sessionLock.unlock()
    case .expired:
      pendingRequests.append((request, completion))
      let id = UUID()
      refreshId = id
      sessionLock.unlock()
      provider.refreshToken { [weak self] result in
        guard let self = self else { return }
        self.queue.async { self.finishRefresh(result, id: id, sessionId: sessionId) }
      }
    }
  }

  private func finishRefresh(_ result: Result<String, Error>, id: UUID, sessionId: UUID) {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    guard self.sessionId == sessionId, refreshId == id else { return }
    refreshId = nil
    let requests = pendingRequests
    pendingRequests.removeAll()
    switch result {
    case let .success(token):
      for pending in requests {
        guard self.sessionId == sessionId else {
          pending.completion(nil)
          continue
        }
        let request = provider.attach(token: token, to: pending.request)
        pending.completion(self.sessionId == sessionId ? request : nil)
      }
    case let .failure(error):
      for pending in requests {
        pending.completion(nil)
      }
      guard self.sessionId == sessionId else { return }
      if case OAuthError.sessionEnded = error {
        return
      }
      failedToRenew(with: error)
    }
  }
}
