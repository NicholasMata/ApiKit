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
  private let queue = DispatchQueue(label: "ApiKit.OAuthInterceptor")
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
  }

  private func failedToRenew(with err: Error?) {
    workItem?.cancel()
    let workItem = DispatchWorkItem(block: { [weak self] in
      self?.onFailedToRenew?(err)
    })
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    self.workItem = workItem
  }

  public func api(_: Api,
                  modifyRequest request: URLRequest,
                  withId _: UUID,
                  onNewRequest: @escaping (URLRequest?) -> Void)
  {
    queue.async { self.prepare(request, completion: onNewRequest) }
  }

  private func prepare(_ request: URLRequest, completion: @escaping (URLRequest?) -> Void) {
    if refreshId != nil {
      pendingRequests.append((request, completion))
      return
    }

    switch provider.tokenState {
    case let .valid(token):
      completion(provider.attach(token: token, to: request))
    case .missing:
      completion(nil)
      failedToRenew(with: OAuthError.noToken)
    case .expired:
      pendingRequests.append((request, completion))
      let id = UUID()
      refreshId = id
      provider.refreshToken { result in
        self.queue.async { self.finishRefresh(result, id: id) }
      }
    }
  }

  private func finishRefresh(_ result: Result<String, Error>, id: UUID) {
    guard refreshId == id else { return }
    refreshId = nil
    let requests = pendingRequests
    pendingRequests.removeAll()
    switch result {
    case let .success(token):
      for pending in requests {
        pending.completion(provider.attach(token: token, to: pending.request))
      }
    case let .failure(error):
      for pending in requests {
        pending.completion(nil)
      }
      failedToRenew(with: error)
    }
  }
}
