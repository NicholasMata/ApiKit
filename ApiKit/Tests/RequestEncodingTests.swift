import ApiKit
import XCTest

final class RequestEncodingTests: XCTestCase {
  private enum EncodingFailure: Error { case fixture }
  private struct Payload: Codable, Equatable {
    let displayName: String
  }

  func testAddingEncodedBodyPreservesHeadersAndSetsContentType() throws {
    var request = URLRequest(url: URL(string: "https://apikit.test")!)
    request.setValue("trace", forHTTPHeaderField: "X-Trace")
    try request.add(encodable: Payload(displayName: "Taylor"))
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Trace"), "trace")
    XCTAssertEqual(try JSONDecoder().decode(Payload.self, from: XCTUnwrap(request.httpBody)), Payload(displayName: "Taylor"))
  }

  func testRequestFactoriesPreserveMethodBodyAndCallerHeaders() throws {
    let endpoint = StaticEndpointInfo(url: "https://apikit.test", headers: ["X-Endpoint": "endpoint", "X-Conflict": "default"])
    let headers = ["X-Caller": "caller", "X-Conflict": "override"]
    let body = Data("raw body".utf8)
    let requests: [(String, HttpRequest)] = [
      ("GET", .get(endpoint: endpoint, path: "/users", headers: headers)),
      ("POST", .post(endpoint: endpoint, path: "/users", rawBody: body, headers: headers)),
      ("PUT", .put(endpoint: endpoint, path: "/users", rawBody: body, headers: headers)),
      ("PATCH", .patch(endpoint: endpoint, path: "/users", rawBody: body, headers: headers)),
      ("DELETE", .delete(endpoint: endpoint, path: "/users", rawBody: body, headers: headers)),
    ]
    for (method, request) in requests {
      let urlRequest = request.urlRequest
      XCTAssertEqual(urlRequest.url?.absoluteString, "https://apikit.test/users")
      XCTAssertEqual(urlRequest.httpMethod, method)
      XCTAssertEqual(urlRequest.httpBody, method == "GET" ? nil : body)
      XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Endpoint"), "endpoint")
      XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Caller"), "caller")
      XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Conflict"), "override")
    }
  }

  func testAddingEncodedBodySetsCustomContentTypeWithOrWithoutHeaders() throws {
    for headers in [[:], ["Content-Type": "old/type", "X-Trace": "trace"]] {
      var request = URLRequest(url: URL(string: "https://apikit.test")!)
      request.allHTTPHeaderFields = headers
      try request.add(encodable: Payload(displayName: "Taylor"), mimeType: "application/custom+json")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/custom+json")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Trace"), headers["X-Trace"])
    }
  }

  func testEncodedFactoriesHonorCustomEncoderAndContentType() throws {
    let endpoint = StaticEndpointInfo(url: "https://apikit.test")
    let payload = Payload(displayName: "Taylor Smith")
    let encoder = URLEncodedFormEncoder(keyEncoding: .convertToSnakeCase, spaceEncoding: .plusReplaced)
    let contentType = "application/x-www-form-urlencoded"
    let requests = [
      try HttpRequest.post(endpoint: endpoint, path: "/users", body: payload, encoder: encoder, contentType: contentType),
      try HttpRequest.put(endpoint: endpoint, path: "/users", body: payload, encoder: encoder, contentType: contentType),
      try HttpRequest.patch(endpoint: endpoint, path: "/users", body: payload, encoder: encoder, contentType: contentType),
    ]
    for request in requests {
      XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), "display_name=Taylor+Smith")
      XCTAssertEqual(request.urlRequest.value(forHTTPHeaderField: "Content-Type"), contentType)
    }
  }

  func testRequestBuilderCombinesEndpointAndCallerHeaders() {
    let api = Api()
    let endpoint = StaticEndpointInfo(url: "https://apikit.test", headers: ["X-Shared": "default", "X-Only": "endpoint"])
    let request = api.request(endpoint: endpoint, path: "/users", method: .get, headers: ["X-Shared": "caller"])
    XCTAssertEqual(request.url?.absoluteString, "https://apikit.test/users")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Shared"), "caller")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Only"), "endpoint")
  }

  func testFormEncodingEscapesOAuthTokenDelimiters() throws {
    let encoder = URLEncodedFormEncoder()
    let value: String = try encoder.encode(["refresh_token": "a+b&c=d% value", "grant_type": "refresh_token"])
    XCTAssertEqual(value, "grant_type=refresh_token&refresh_token=a%2Bb%26c%3Dd%25%20value")
  }

  func testFormArrayStrategies() throws {
    let strategies: [(URLEncodedFormEncoder.ArrayEncoding, String)] = [
      (.brackets, "values%5B%5D=a&values%5B%5D=b"),
      (.noBrackets, "values=a&values=b"),
      (.indexInBrackets, "values%5B0%5D=a&values%5B1%5D=b"),
    ]
    for (strategy, expected) in strategies {
      let encoded: String = try URLEncodedFormEncoder(arrayEncoding: strategy).encode(["values": ["a", "b"]])
      XCTAssertEqual(encoded, expected)
    }
  }

  func testFormBooleanAndNestedObjectStrategies() throws {
    struct Form: Encodable {
      let enabled = true
      let disabled = false
      let user = Payload(displayName: "Taylor")
    }
    let numeric: String = try URLEncodedFormEncoder().encode(Form())
    XCTAssertEqual(numeric, "disabled=0&enabled=1&user%5BdisplayName%5D=Taylor")
    let literal: String = try URLEncodedFormEncoder(boolEncoding: .literal).encode(Form())
    XCTAssertEqual(literal, "disabled=false&enabled=true&user%5BdisplayName%5D=Taylor")
  }

  func testFormKeyStrategies() throws {
    let strategies: [(URLEncodedFormEncoder.KeyEncoding, String)] = [
      (.useDefaultKeys, "displayName"), (.convertToSnakeCase, "display_name"),
      (.convertToKebabCase, "display-name"), (.capitalized, "DisplayName"),
      (.uppercased, "DISPLAYNAME"), (.lowercased, "displayname"),
      (.custom { "custom_" + $0 }, "custom_displayName"),
    ]
    for (strategy, key) in strategies {
      let encoded: String = try URLEncodedFormEncoder(keyEncoding: strategy).encode(Payload(displayName: "Taylor"))
      XCTAssertEqual(encoded, "\(key)=Taylor")
    }
  }

  func testFormRejectsScalarAndArrayRoots() {
    let encoder = URLEncodedFormEncoder()
    XCTAssertThrowsError(try encoder.encode("scalar") as String)
    XCTAssertThrowsError(try encoder.encode([1, 2]) as String)
  }

  func testEncoderFailurePropagatesWithoutCreatingRequest() {
    struct Invalid: Encodable {
      func encode(to _: Encoder) throws { throw EncodingFailure.fixture }
    }
    XCTAssertThrowsError(try HttpRequest.post("https://apikit.test", body: Invalid())) { error in
      XCTAssertTrue(error is EncodingFailure)
    }
  }
}
