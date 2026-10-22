import ApiKit
import XCTest

/// Exercises URLSession and the complete response pipeline without public services.
final class ApiIntegrationTests: XCTestCase {
  private struct User: Codable, Equatable {
    let id: Int
    let name: String
  }

  private var session: URLSession!
  private var api: Api!
  private var url: URL!

  override func setUp() {
    super.setUp()
    url = URL(string: "https://\(UUID().uuidString).apikit.test/users")!
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureURLProtocol.self]
    session = URLSession(configuration: configuration)
    api = Api(urlSession: session)
    respond()
  }

  override func tearDown() {
    session.invalidateAndCancel()
    FixtureURLProtocol.remove(url)
    api = nil
    session = nil
    super.tearDown()
  }

  private func respond(status: Int = 200, body: String = "{\"id\":1,\"name\":\"Taylor\"}") {
    FixtureURLProtocol.register(url) { protocolInstance in
      let response = HTTPURLResponse(url: protocolInstance.request.url!, statusCode: status,
                                     httpVersion: nil, headerFields: ["X-Fixture": "local"])!
      protocolInstance.client?.urlProtocol(protocolInstance, didReceive: response, cacheStoragePolicy: .notAllowed)
      protocolInstance.client?.urlProtocol(protocolInstance, didLoad: Data(body.utf8))
      protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
    }
  }

  func testDecodedResponsePreservesHTTPMetadata() {
    let completed = expectation(description: "Decoded HTTP response")
    api.send(URLRequest(url: url)) { (result: Result<HttpResponse<User>, Error>) in
      defer { completed.fulfill() }
      do {
        let response = try result.get()
        XCTAssertEqual(response.body, User(id: 1, name: "Taylor"))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.value(forHTTPHeaderField: "x-fixture"), "local")
        XCTAssertEqual(response.url, self.url)
      } catch { XCTFail("Unexpected error: \(error)") }
    }
    wait(for: [completed], timeout: 5)
  }

  func testConcurrentRequestsDecodeIndependently() {
    let completed = expectation(description: "Concurrent requests")
    completed.expectedFulfillmentCount = 25
    completed.assertForOverFulfill = true
    for _ in 0 ..< 25 {
      api.send(HttpRequest.get(url)) { (result: Result<User, Error>) in
        XCTAssertEqual(try? result.get(), User(id: 1, name: "Taylor"))
        completed.fulfill()
      }
    }
    wait(for: [completed], timeout: 5)
  }

  func testPostSendsEncodedBodyAndHeaders() throws {
    let received = expectation(description: "POST request reached URLSession")
    FixtureURLProtocol.register(url) { instance in
      XCTAssertEqual(instance.request.httpMethod, "POST")
      XCTAssertEqual(instance.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
      // URLSession may expose an upload through httpBodyStream rather than httpBody.
      var body = instance.request.httpBody ?? Data()
      if let stream = instance.request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
          let count = stream.read(&buffer, maxLength: buffer.count)
          guard count > 0 else { break }
          body.append(contentsOf: buffer.prefix(count))
        }
      }
      XCTAssertEqual(try? JSONDecoder().decode(User.self, from: body), User(id: 2, name: "Morgan"))
      received.fulfill()
      instance.client?.urlProtocol(instance, didFailWithError: URLError(.cancelled))
    }
    let completed = expectation(description: "POST completes")
    api.send(try HttpRequest.post(url, body: User(id: 2, name: "Morgan"))) {
      (result: Result<HttpDataResponse, Error>) in
      if case .success = result { XCTFail("Expected fixture error") }
      completed.fulfill()
    }
    wait(for: [received, completed], timeout: 5)
  }

  func testBadStatusRetainsResponseAndSkipsDecoding() {
    respond(status: 401, body: "unauthorized")
    let completed = expectation(description: "Bad status")
    api.send(URLRequest(url: url)) { (result: Result<User, Error>) in
      guard case let .failure(ApiError.badStatusCode(_, response)) = result else {
        XCTFail("Expected badStatusCode, got \(result)")
        completed.fulfill()
        return
      }
      XCTAssertEqual(response.statusCode, 401)
      XCTAssertEqual(String(data: response.data, encoding: .utf8), "unauthorized")
      completed.fulfill()
    }
    wait(for: [completed], timeout: 5)
  }

  func testMalformedJSONRetainsResponseAndUnderlyingError() {
    respond(body: "not JSON")
    let completed = expectation(description: "Decoding error")
    api.send(URLRequest(url: url)) { (result: Result<User, Error>) in
      guard case let .failure(ApiError.serializationFailed(error, response)) = result else {
        XCTFail("Expected serializationFailed, got \(result)")
        completed.fulfill()
        return
      }
      XCTAssertTrue(error is DecodingError)
      XCTAssertEqual(response.statusCode, 200)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 5)
  }

  func testConfiguredDecoderAndPerRequestOverride() {
    struct Profile: Decodable { let displayName: String }
    respond(body: "{\"display_name\":\"Taylor\"}")
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    api.config = DefaultApiConfig(decoder: decoder)
    let configured = expectation(description: "Configured decoder")
    api.send(URLRequest(url: url)) { (result: Result<Profile, Error>) in
      XCTAssertEqual(try? result.get().displayName, "Taylor")
      configured.fulfill()
    }
    let overridden = expectation(description: "Per request decoder overrides config")
    api.send(URLRequest(url: url), decoder: JSONDecoder()) { (result: Result<Profile, Error>) in
      if case .failure(ApiError.serializationFailed) = result {} else {
        XCTFail("Expected the explicit decoder to reject snake_case keys")
      }
      overridden.fulfill()
    }
    wait(for: [configured, overridden], timeout: 5)
  }

  func testDefaultStatusValidationBoundariesAndEmptyBody() {
    for status in [199, 200, 204, 299, 300, 404, 500] {
      respond(status: status, body: "")
      let completed = expectation(description: "Status \(status)")
      api.send(URLRequest(url: url)) { (result: Result<HttpDataResponse, Error>) in
        defer { completed.fulfill() }
        switch result {
        case let .success(response):
          XCTAssertTrue((200 ... 299).contains(status))
          XCTAssertEqual(response.statusCode, status)
          XCTAssertTrue(response.data.isEmpty)
        case let .failure(ApiError.badStatusCode(_, response)):
          XCTAssertFalse((200 ... 299).contains(status))
          XCTAssertEqual(response.statusCode, status)
        case let .failure(error): XCTFail("Unexpected error: \(error)")
        }
      }
      wait(for: [completed], timeout: 5)
    }
  }

  func testTransportTimeoutIsForwardedUnchanged() {
    FixtureURLProtocol.register(url) { instance in
      instance.client?.urlProtocol(instance, didFailWithError: URLError(.timedOut))
    }
    let completed = expectation(description: "Transport error")
    api.send(URLRequest(url: url)) { (result: Result<HttpDataResponse, Error>) in
      guard case let .failure(error) = result else {
        XCTFail("Expected transport error")
        completed.fulfill()
        return
      }
      XCTAssertEqual((error as? URLError)?.code, .timedOut)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 5)
  }

  func testNonHTTPResponseIsRejected() {
    FixtureURLProtocol.register(url) { instance in
      let response = URLResponse(url: instance.request.url!, mimeType: nil,
                                 expectedContentLength: 0, textEncodingName: nil)
      instance.client?.urlProtocol(instance, didReceive: response, cacheStoragePolicy: .notAllowed)
      instance.client?.urlProtocolDidFinishLoading(instance)
    }
    let completed = expectation(description: "Non HTTP response")
    api.send(URLRequest(url: url)) { (result: Result<HttpDataResponse, Error>) in
      if case .failure(ApiError.notHttpRequest) = result {} else { XCTFail("Unexpected result: \(result)") }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 5)
  }

  func testDownloadWritesAndOverwritesFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for body in ["first contents", "replacement"] {
      respond(body: body)
      let completed = expectation(description: "Download \(body)")
      api.download(HttpRequest.get(url), to: directory, asFileName: "fixture.txt") { result in
        do {
          let file = try result.get()
          XCTAssertEqual(file, directory.appendingPathComponent("fixture.txt"))
          XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), body)
        } catch { XCTFail("Unexpected error: \(error)") }
        completed.fulfill()
      }
      wait(for: [completed], timeout: 5)
    }
  }

  func testDownloadReportsWriteFailure() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let completed = expectation(description: "File write fails")
    api.download(URLRequest(url: url), to: missing, asFileName: "fixture.txt") { result in
      if case .success = result { XCTFail("Expected failure for missing directory") }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 5)
  }

  @available(iOS 13.0, *)
  func testAsyncResponseAndDownload() async throws {
    let user: User = try await api.send(HttpRequest.get(url))
    XCTAssertEqual(user, User(id: 1, name: "Taylor"))
    let response: HttpResponse<User> = try await api.send(URLRequest(url: url))
    XCTAssertEqual(response.body, user)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = try await api.download(URLRequest(url: url), to: directory, asFileName: "user.json")
    XCTAssertEqual(try JSONDecoder().decode(User.self, from: Data(contentsOf: file)), user)
  }
}

private final class FixtureURLProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var handlers: [URL: (FixtureURLProtocol) -> Void] = [:]

  static func register(_ url: URL, handler: @escaping (FixtureURLProtocol) -> Void) {
    lock.lock()
    handlers[url] = handler
    lock.unlock()
  }

  static func remove(_ url: URL) {
    lock.lock()
    handlers.removeValue(forKey: url)
    lock.unlock()
  }

  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.lock()
    let handler = request.url.flatMap { Self.handlers[$0] }
    Self.lock.unlock()
    guard let handler = handler else {
      XCTFail("Unregistered fixture: \(request)")
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    handler(self)
  }

  override func stopLoading() {}
}
