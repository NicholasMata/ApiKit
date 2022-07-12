//
//  OAuthInterceptor.swift
//
//
//  Created by Nicholas Mata on 6/14/22.
//

import Foundation

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

  public func api(_: Api,
                  modifyRequest request: URLRequest,
                  withId _: UUID,
                  onNewRequest: @escaping (URLRequest) -> Void)
  {
    guard provider.hasPreviousSignIn() else {
      onNewRequest(request)
      return
    }

    semaphore.wait()
    guard let token = provider.token else {
      semaphore.signal()
      failedToRenew(with: nil)
      return
    }
    let newRequest = provider.modify(request: request, token: token)
    semaphore.signal()
    onNewRequest(newRequest)
  }

  public func api(_ api: Api,
                  didReceive result: Result<HttpDataResponse, Error>,
                  withId _: UUID,
                  for request: URLRequest,
                  completion: HttpDataCompletion) -> Bool
  {
    guard case let .success(response) = result,
          response.statusCode == 401
    else {
      return false
    }

    semaphore.wait()

    guard provider.hasPreviousSignIn()
    else {
      semaphore.signal()
      failedToRenew(with: nil)
      return true
    }

    provider.restorePreviousSignIn { result in
      switch result {
      case let .success(newToken):
        self.semaphore.signal()
        let newRequest = self.provider.modify(request: request, token: newToken)
        _ = api.send(newRequest, completion: completion)
      case let .failure(err):
        self.semaphore.signal()
        self.failedToRenew(with: err)
      }
    }
    return true
  }
}
