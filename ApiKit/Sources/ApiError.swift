//
//  ApiError.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// A list of errors that can occur because of API issues.
public enum ApiError: Error {
  /// A bad status code occurred.
  case badStatusCode(error: Any?, response: HttpDataResponse)
  /// Serialized of response body failed.
  case serializationFailed(error: Error, response: HttpDataResponse)
  /// Occurs when a request was not HTTP or HTTPS request.
  case notHttpRequest
}
