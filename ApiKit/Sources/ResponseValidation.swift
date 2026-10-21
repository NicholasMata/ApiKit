import Foundation

/// A check applied to a successful transport result before decoding its body.
public enum ResponseValidation {
  /// Removes all configured checks when passed to `ApiCall.validating`.
  case none
  /// Accepts only the supplied HTTP status codes. An empty list rejects every status.
  case statusCode([Int])
  /// Requires a matching Content-Type, ignoring case and parameters such as charset.
  /// Supports exact MIME types, `type/*`, and `*/*`. A missing Content-Type fails.
  case contentType([String])
  /// Accepts the response unless the closure throws. The thrown error is delivered unchanged.
  case custom((HttpDataResponse) throws -> Void)

  /// Accepts HTTP status codes 200 through 299.
  public static var statusCode: ResponseValidation {
    .statusCode(Array(200 ... 299))
  }

  func validate(_ response: HttpDataResponse) throws {
    switch self {
    case .none:
      break
    case let .statusCode(codes):
      guard codes.contains(response.statusCode) else {
        throw ApiError.badStatusCode(error: nil, response: response)
      }
    case let .contentType(types):
      let actual = response.value(forHTTPHeaderField: "Content-Type").map(Self.mimeType)
      guard let actual = actual, types.contains(where: { Self.matches(actual, expected: Self.mimeType($0)) }) else {
        throw ResponseValidationError.unacceptableContentType(acceptable: types, response: response)
      }
    case let .custom(check):
      try check(response)
    }
  }

  private static func mimeType(_ value: String) -> String {
    value.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func matches(_ actual: String, expected: String) -> Bool {
    let actualParts = actual.split(separator: "/", omittingEmptySubsequences: false)
    let expectedParts = expected.split(separator: "/", omittingEmptySubsequences: false)
    guard actualParts.count == 2, expectedParts.count == 2,
          actualParts.allSatisfy({ !$0.isEmpty }), expectedParts.allSatisfy({ !$0.isEmpty }) else { return false }
    if expectedParts[0] == "*" {
      return expectedParts[1] == "*"
    }
    return actualParts[0] == expectedParts[0] && (expectedParts[1] == "*" || actualParts[1] == expectedParts[1])
  }
}

/// A response failed a built-in validation other than HTTP status validation.
/// Status validation continues to use `ApiError.badStatusCode`.
public enum ResponseValidationError: Error {
  /// The response's Content-Type was absent or did not match any accepted MIME type.
  case unacceptableContentType(acceptable: [String], response: HttpDataResponse)
}
