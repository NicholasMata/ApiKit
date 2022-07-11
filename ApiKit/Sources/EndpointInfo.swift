//
//  EndpointInfo.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// Static Endpoint information a basic implementation of EndpointInfo
struct StaticEndpointInfo: EndpointInfo {
  var url: String
  var headers: [String: String] = [:]
}

/// Endpoint information used to tie url and headers.
public protocol EndpointInfo {
  /// The base url or domain.
  var url: String { get }
  /// The headers to be applied for this url or domain.
  var headers: [String: String] { get }
}
