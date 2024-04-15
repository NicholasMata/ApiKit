//
//  ApiConfig.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// A default ApiConfig so that you don't have to create one for basic implements.
public class DefaultApiConfig: ApiConfig {
  /// The interceptors the Api will use.
  public var interceptors: [ApiInterceptor]
  /// The default decoder the Api will use.
  public var decoder: DataDecoder
  /// An operation queue that response completion and interceptors will be executed on.
  public var responseQueue: OperationQueue
  /// An operation queue that the request and interceptors will be executed on.
  public var requestQueue: OperationQueue
  
  
  /// Initializes a DefaultApiConfig which can be used by an Api
  /// - Parameters:
  ///   - decoder: The default decoder.
  ///   - interceptors: The interceptors that will be used.
  public init(decoder: JSONDecoder = .init(), interceptors: [ApiInterceptor] = [],
              requestQueue: OperationQueue = OperationQueue(),
              responseQueue: OperationQueue = OperationQueue()) {
    self.decoder = decoder
    self.interceptors = interceptors
    self.requestQueue = requestQueue
    self.responseQueue = responseQueue
  }

  public func headerConflictHandler(a: String, b _: String) -> String {
    return a
  }
}

/// Used to configure an API.
public protocol ApiConfig {
  /// The interceptors that the API will use.
  var interceptors: [ApiInterceptor] { get }
  /// The default decoder that the API will use.
  var decoder: DataDecoder { get }
  /// An operation queue that response completion and interceptors will be executed on.
  var responseQueue: OperationQueue { get }
  /// An operation queue that the request and interceptors will be executed on.
  var requestQueue: OperationQueue { get }

  /// Used to resolve header conflicts when two headers are merged.
  /// - Parameters:
  ///   - a: The left set of header.
  ///   - b: The right set of header.
  /// - Returns: The header to use.
  func headerConflictHandler(a: String, b: String) -> String
}
