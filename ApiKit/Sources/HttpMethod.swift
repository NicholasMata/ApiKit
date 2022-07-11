//
//  HttpMethod.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// HTTP Methods, can be extended if more as needed.
public struct HttpMethod: RawRepresentable {
  /// The GET method requests a representation of the specified resource. Requests using GET should only retrieve data.
  public static let get = HttpMethod(rawValue: "GET")
  /// The PUT method replaces all current representations of the target resource with the request payload.
  public static let put = HttpMethod(rawValue: "PUT")
  /// The POST method submits an entity to the specified resource, often causing a change in state or side effects on the server.
  public static let post = HttpMethod(rawValue: "POST")
  /// The PATCH method applies partial modifications to a resource.
  public static let patch = HttpMethod(rawValue: "PATCH")
  /// The DELETE method deletes the specified resource.
  public static let delete = HttpMethod(rawValue: "DELETE")
  
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}
