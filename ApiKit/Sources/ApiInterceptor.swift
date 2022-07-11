//
//  ApiInterceptor.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// Used to intercept or inject code before a request is sent or once a response is received to change functionality.
public protocol ApiInterceptor {
  /// Called once a response for a Api Request is recieved.
  /// - Parameters:
  ///   - api: The api that received the response.
  ///   - response: The response that was received or error.
  ///   - identifier: An identifier representing the request.
  ///   - request: The request that was sent to get this response.
  ///   - completion: The completion handler that should be called if the interceptor has handled the response.
  /// - Returns: Either true or false indicating that the interceptor has handled the response or will handle the response.
  func api(_ api: Api,
           didReceive result: Result<HttpDataResponse, Error>,
           withId identifier: UUID,
           for request: URLRequest,
           completion: HttpDataCompletion) -> Bool

  /// Called before request is sent, so that it can be intercepted.
  /// - Parameters:
  ///   - api: The api that the request was sent to.
  ///   - request: The request that will be sent.
  ///   - identifier: An identifier representing the request.
  ///   - completion: Called if the api result should be called early.
  /// - Returns: Either true or false indicating that the interceptor has handled the response or will handle the response.
  func api(_ api: Api,
           willSendRequest request: URLRequest,
           withId identifier: UUID,
           completion: HttpDataCompletion) -> Bool

  /// Called before request is sent, so that any modifications that need to occur can.
  /// - Parameters:
  ///   - api: The api that the request was sent to.
  ///   - request: The request to modify.
  ///   - identifier: An identifier representing the request.
  ///   - onNewRequest: Should be called with the new/modified request or the original request if no change.
  func api(_ api: Api,
           modifyRequest request: URLRequest,
           withId identifier: UUID,
           onNewRequest: @escaping (URLRequest) -> Void) -> Void
}

public extension ApiInterceptor where Self: AnyObject {
  func api(_: Api,
           didReceive _: Result<HttpDataResponse, Error>,
           withId _: UUID,
           for _: URLRequest,
           completion _: HttpDataCompletion) -> Bool
  {
    return false
  }

  func api(_: Api,
           modifyRequest request: URLRequest,
           withId _: UUID,
           onNewRequest: @escaping (URLRequest) -> Void)
  {
    onNewRequest(request)
  }

  func api(_: Api,
           willSendRequest _: URLRequest,
           withId _: UUID,
           completion _: HttpDataCompletion) -> Bool
  {
    return false
  }
}
