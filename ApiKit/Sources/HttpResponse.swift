//
//  ApiHttpResponse.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// A wrapper around HTTPURLResponse for easy access to important information this includes a decoded response body.
public class HttpResponse<T: Decodable>: HttpDataResponse {
  /// The body for the response deserialized.
  public var body: T

  convenience init(rawResponse: HttpDataResponse, body: T) {
    self.init(response: rawResponse.response, data: rawResponse.data, body: body)
  }

  public init(response: HTTPURLResponse, data: Data, body: T) {
    self.body = body
    super.init(response: response, data: data)
  }
}

/// A wrapper around HTTPURLResponse for easy access to important information.
public class HttpDataResponse {
  /// The status code for the response.
  public var statusCode: Int {
    return response.statusCode
  }

  /// Status code is in the 200 range indicating a successful request..
  public var successful: Bool {
    return 200 ... 299 ~= response.statusCode
  }

  /// The headers for the response.
  public var allHeaderFields: [AnyHashable: Any] {
    return response.allHeaderFields
  }

  /// The url for the response.
  public var url: URL? {
    return response.url
  }

  /// The original HTTPURLResponse that this class wraps.
  public let response: HTTPURLResponse

  /// The body for the response as data.
  public var data: Data

  public init(response: HTTPURLResponse, data: Data) {
    self.response = response
    self.data = data
  }

  /// Get a value for a specific header key.
  /// - Parameter field: The header key you want the value for, case-insensitive.
  /// - Returns: The header value for the given key.
  open func value(forHTTPHeaderField field: String) -> String? {
    if #available(iOS 13.0, *) {
      return response.value(forHTTPHeaderField: field)
    } else {
      let element = allHeaderFields.first(where: { $0.key.description.lowercased() == field.lowercased() })
      return element?.value as? String
    }
  }
}

extension HttpDataResponse: CustomStringConvertible {
  public var description: String {
    var message = response.description
    if let stringContent = String(data: data, encoding: .utf8) {
      message += "\n\n \(stringContent)"
    }
    return message
  }
}
