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
}

/// Used to add OAuth access token to request for authentication / authorization.
open class OAuthInterceptor: ApiInterceptor {
  private let semaphore = DispatchSemaphore(value: 1)
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
  }

  private func failedToRenew(with err: Error?) {
    workItem?.cancel()
    let workItem = DispatchWorkItem(block: { [weak self] in
      self?.onFailedToRenew?(err)
    })
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    self.workItem = workItem
  }

  public func api(_ api: Api,
                  modifyRequest request: URLRequest,
                  withId _: UUID,
                  onNewRequest: @escaping (URLRequest?) -> Void)
  {
    semaphore.wait()
    let tokenState = provider.tokenState
    guard tokenState == TokenState.expired else {
      self.semaphore.signal()
      if case let .valid(token) = tokenState {
        let newRequest = provider.attach(token: token, to: request)
        onNewRequest(newRequest)
      } else {
        onNewRequest(nil)
        self.failedToRenew(with: OAuthError.noToken)
      }
      return
    }

    provider.refreshToken { result in
      switch result {
      case let .success(token):
        let newRequest = self.provider.attach(token: token, to: request)
        self.semaphore.signal()
        onNewRequest(newRequest)
      case let .failure(error):
        self.semaphore.signal()
        onNewRequest(nil)
        self.failedToRenew(with: error)
      }
    }
  }
}
