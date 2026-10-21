import ApiKit
import XCTest

final class ApiValidationTests: XCTestCase {
  private let request = URLRequest(url: URL(string: "https://apikit.test/validation")!)

  func testLegacyAndFluentCallsKeepDefaultStatusValidation() {
    for status in [200, 404] {
      let api = makeApi(status: status)
      let completed = expectation(description: "Legacy request completes")
      api.send(request) { (result: Result<HttpDataResponse, Error>) in
        if status == 200 {
          XCTAssertEqual(self.success(result)?.statusCode, status)
        } else {
          self.assertBadStatus(result, code: status)
        }
        completed.fulfill()
      }
      wait(for: [completed], timeout: 2)
      run(api.using(request)) { result in
        if status == 200 {
          XCTAssertEqual(self.success(result)?.statusCode, status)
        } else {
          self.assertBadStatus(result, code: status)
        }
      }
    }
  }

  func testExplicitStatusCodesReplaceDefaultAndPreviousStatusPolicy() {
    let api = makeApi(status: 404)
    run(api.using(request).validating(.statusCode([200])).validating(.statusCode([404]))) { result in
      XCTAssertEqual(self.success(result)?.statusCode, 404)
    }
    run(api.using(request).validating(.statusCode([404])).validating(.statusCode)) { result in
      self.assertBadStatus(result, code: 404)
    }
  }

  func testExplicitStatusPolicyRejectsUnlistedCodes() {
    run(makeApi(status: 500).using(request).validating(.statusCode([200, 404]))) { result in
      self.assertBadStatus(result, code: 500)
    }
    run(makeApi().using(request).validating(.statusCode([]))) { result in
      self.assertBadStatus(result, code: 200)
    }
  }

  func testNoneAcceptsAnyStatusAndPreservesResponseBody() {
    run(makeApi(status: 503, body: "server error").using(request).validating(.none)) { result in
      let response = self.success(result)
      XCTAssertEqual(response?.statusCode, 503)
      XCTAssertEqual(response?.data, Data("server error".utf8))
    }
  }

  func testNoneClearsAllChecksAndLaterChecksAccumulate() {
    let call = makeApi(status: 404, contentType: nil).using(request)
      .validating(.custom { _ in XCTFail("Cleared check must not run") })
      .validating(.contentType(["application/json"]))
      .validating(.none)
      .validating(.custom { response in XCTAssertEqual(response.statusCode, 404) })
    run(call) { result in XCTAssertNotNil(self.success(result)) }
  }

  func testAddingStatusAfterNoneRestoresStatusValidation() {
    run(makeApi(status: 404).using(request).validating(.none).validating(.statusCode)) { result in
      self.assertBadStatus(result, code: 404)
    }
  }

  func testBuilderIsLazyAndBranchesHaveIndependentValidation() {
    let api = makeApi(status: 404)
    let original = api.using(request)
    let relaxed = original.validating(.none)
    XCTAssertEqual(api.config.requestQueue.operationCount, 0)
    run(relaxed) { result in XCTAssertNotNil(self.success(result)) }
    run(original) { result in self.assertBadStatus(result, code: 404) }
  }

  func testContentTypeIgnoresCaseAndCharsetParameters() {
    let call = makeApi(contentType: "Application/JSON; charset=UTF-8").using(request)
      .validating(.statusCode)
      .validating(.contentType(["APPLICATION/JSON"]))
    run(call) { result in XCTAssertNotNil(self.success(result)) }
  }

  func testContentTypeSupportsMimeWildcards() {
    for accepted in [["application/*"], ["*/*"], ["text/plain", "application/json"]] {
      run(makeApi().using(request).validating(.contentType(accepted))) { result in
        XCTAssertNotNil(self.success(result))
      }
    }
  }

  func testContentTypeRejectsMismatchedMissingAndEmptyAcceptedTypes() {
    for contentType in ["text/html", nil] as [String?] {
      let call = makeApi(contentType: contentType).using(request).validating(.contentType(["application/json"]))
      run(call) { result in
        guard case let .failure(ResponseValidationError.unacceptableContentType(acceptable, response)) = result else {
          XCTFail("Expected content type validation error, got \(result)")
          return
        }
        XCTAssertEqual(acceptable, ["application/json"])
        XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), contentType)
      }
    }
    run(makeApi().using(request).validating(.contentType([]))) { result in
      guard case .failure(ResponseValidationError.unacceptableContentType) = result else {
        XCTFail("An empty accepted MIME list must reject the response")
        return
      }
    }
  }

  func testAddingContentTypeKeepsDefaultStatusValidation() {
    run(makeApi(status: 404).using(request).validating(.contentType(["application/json"]))) { result in
      self.assertBadStatus(result, code: 404)
    }
  }

  func testCustomChecksRunInOrderAndFirstErrorStopsValidation() {
    var checks: [Int] = []
    let call = makeApi().using(request)
      .validating(.custom { _ in checks.append(1) })
      .validating(.custom { _ in
        checks.append(2)
        throw ValidationTestError.rejected
      })
      .validating(.custom { _ in XCTFail("Checks after a failure must not run") })
    run(call) { result in
      guard case .failure(ValidationTestError.rejected) = result else {
        XCTFail("Expected the unchanged custom error, got \(result)")
        return
      }
      XCTAssertEqual(checks, [1, 2])
    }
  }

  func testInterceptorsThenValidationThenCompletionRunOnResponseQueue() {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    var stages: [String] = []
    let api = makeApi(responseQueue: queue, onReceive: { _, _ in
      XCTAssertTrue(OperationQueue.current === queue)
      stages.append("interceptor")
      return false
    })
    let call = api.using(request).validating(.custom { _ in
      XCTAssertTrue(OperationQueue.current === queue)
      stages.append("validation")
    })
    run(call) { result in
      XCTAssertTrue(OperationQueue.current === queue)
      XCTAssertNotNil(self.success(result))
      stages.append("completion")
      XCTAssertEqual(stages, ["interceptor", "validation", "completion"])
    }
  }

  func testHandledResponseInterceptorPreservesExistingValidationBypass() {
    let api = makeApi(status: 404, onReceive: { result, complete in
      complete?(result)
      return true
    })
    let completed = expectation(description: "Legacy interceptor retains final result control")
    api.send(request) { (result: Result<HttpDataResponse, Error>) in
      XCTAssertEqual(self.success(result)?.statusCode, 404)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
    run(api.using(request).validating(.custom { _ in XCTFail("Handled response bypasses checks") })) { result in
      XCTAssertEqual(self.success(result)?.statusCode, 404)
    }
  }

  func testTransportFailureIsPreservedWithoutRunningValidators() {
    let stub = ValidationResponseInterceptor(result: .failure(URLError(.timedOut)))
    let api = Api(config: DefaultApiConfig(interceptors: [stub]))
    run(api.using(request).validating(.custom { _ in XCTFail("There is no response to validate") })) { result in
      guard case let .failure(error as URLError) = result else {
        XCTFail("Expected original transport error, got \(result)")
        return
      }
      XCTAssertEqual(error.code, .timedOut)
    }
  }

  func testFluentDecodedBodyAndResponseUseConfiguredValidation() throws {
    let call = try makeApi(status: 404).using(HttpRequest.get(XCTUnwrap(request.url))).validating(.none)
    let completed = expectation(description: "Both decoded completion forms succeed")
    completed.expectedFulfillmentCount = 2
    call.send { (result: Result<ValidationPayload, Error>) in
      switch result {
      case let .success(body): XCTAssertEqual(body.message, "ok")
      case let .failure(error): XCTFail("Unexpected error: \(error)")
      }
      completed.fulfill()
    }
    call.send { (result: Result<HttpResponse<ValidationPayload>, Error>) in
      switch result {
      case let .success(response):
        XCTAssertEqual(response.statusCode, 404)
        XCTAssertEqual(response.body.message, "ok")
      case let .failure(error): XCTFail("Unexpected error: \(error)")
      }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
  }

  func testLegacyTypedAndDownloadCallsKeepStatusValidation() {
    let api = makeApi(status: 404)
    let completed = expectation(description: "Existing overloads still reject bad status")
    completed.expectedFulfillmentCount = 3
    api.send(request) { (result: Result<ValidationPayload, Error>) in
      guard case .failure(ApiError.badStatusCode) = result else {
        XCTFail("Expected legacy body decoding to reject bad status")
        completed.fulfill()
        return
      }
      completed.fulfill()
    }
    api.send(request) { (result: Result<HttpResponse<ValidationPayload>, Error>) in
      guard case .failure(ApiError.badStatusCode) = result else {
        XCTFail("Expected legacy response decoding to reject bad status")
        completed.fulfill()
        return
      }
      completed.fulfill()
    }
    api.download(request, asFileName: "must-not-write") { result in
      guard case .failure(ApiError.badStatusCode) = result else {
        XCTFail("Expected legacy download to reject bad status")
        completed.fulfill()
        return
      }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
  }

  func testValidationFailurePrecedesDecodingAndDecodeErrorsKeepExistingShape() {
    let completed = expectation(description: "Validation and decoding failures retain their types")
    completed.expectedFulfillmentCount = 2
    makeApi(body: "invalid JSON").using(request)
      .validating(.custom { _ in throw ValidationTestError.rejected })
      .send { (result: Result<ValidationPayload, Error>) in
        guard case .failure(ValidationTestError.rejected) = result else {
          XCTFail("Validation should fail before decoding")
          completed.fulfill()
          return
        }
        completed.fulfill()
      }
    makeApi(body: "invalid JSON").using(request)
      .send { (result: Result<ValidationPayload, Error>) in
        guard case .failure(ApiError.serializationFailed) = result else {
          XCTFail("Expected the existing serialization error wrapper")
          completed.fulfill()
          return
        }
        completed.fulfill()
      }
    wait(for: [completed], timeout: 2)
  }

  @available(iOS 13.0, *)
  func testAsyncBuilderSupportsAllResponseForms() async throws {
    let call = makeApi(status: 404).using(request).validating(.none)
    let raw: HttpDataResponse = try await call.send()
    let response: HttpResponse<ValidationPayload> = try await call.send()
    let body: ValidationPayload = try await call.send()
    XCTAssertEqual(raw.statusCode, 404)
    XCTAssertEqual(response.statusCode, 404)
    XCTAssertEqual(response.body.message, "ok")
    XCTAssertEqual(body.message, "ok")
  }

  @available(iOS 13.0, *)
  func testAsyncBuilderCancellationStillCancelsPendingOperation() async {
    let intercepted = expectation(description: "Request is pending in interceptor")
    let stub = ValidationResponseInterceptor(result: .failure(ValidationTestError.rejected), onSend: { _ in
      intercepted.fulfill()
    })
    let api = Api(config: DefaultApiConfig(interceptors: [stub]))
    let completed = expectation(description: "Cancelled async builder returns")
    let task = Task {
      do {
        let _: HttpDataResponse = try await api.using(request).validating(.none).send()
        XCTFail("Expected cancellation")
      } catch {
        if case ApiError.cancelled = error {} else {
          XCTFail("Unexpected error: \(error)")
        }
      }
      completed.fulfill()
    }
    await fulfillment(of: [intercepted], timeout: 2)
    task.cancel()
    await fulfillment(of: [completed], timeout: 2)
  }

  private func makeApi(status: Int = 200, contentType: String? = "application/json",
                       body: String = #"{"message":"ok"}"#, responseQueue: OperationQueue = OperationQueue(),
                       onReceive: ((Result<HttpDataResponse, Error>, HttpDataCompletion) -> Bool)? = nil) -> Api
  {
    let headers = contentType.map { ["Content-Type": $0] }
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
    let result = HttpDataResponse(response: response, data: Data(body.utf8))
    let stub = ValidationResponseInterceptor(result: .success(result), onReceive: onReceive)
    return Api(config: DefaultApiConfig(interceptors: [stub], responseQueue: responseQueue))
  }

  private func run(_ call: ApiCall, check: @escaping (Result<HttpDataResponse, Error>) -> Void) {
    let completed = expectation(description: "Configured request completes once")
    completed.assertForOverFulfill = true
    call.send { (result: Result<HttpDataResponse, Error>) in
      check(result)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
  }

  private func success(_ result: Result<HttpDataResponse, Error>,
                       file: StaticString = #filePath, line: UInt = #line) -> HttpDataResponse?
  {
    switch result {
    case let .success(response): return response
    case let .failure(error):
      XCTFail("Unexpected error: \(error)", file: file, line: line)
      return nil
    }
  }

  private func assertBadStatus(_ result: Result<HttpDataResponse, Error>, code: Int,
                               file: StaticString = #filePath, line: UInt = #line)
  {
    guard case let .failure(ApiError.badStatusCode(_, response)) = result else {
      XCTFail("Expected badStatusCode, got \(result)", file: file, line: line)
      return
    }
    XCTAssertEqual(response.statusCode, code, file: file, line: line)
  }
}

private struct ValidationPayload: Decodable {
  let message: String
}

private enum ValidationTestError: Error {
  case rejected
}

private final class ValidationResponseInterceptor: ApiInterceptor {
  private let result: Result<HttpDataResponse, Error>
  private let onReceive: ((Result<HttpDataResponse, Error>, HttpDataCompletion) -> Bool)?
  private let onSend: ((HttpDataCompletion) -> Void)?

  init(result: Result<HttpDataResponse, Error>,
       onReceive: ((Result<HttpDataResponse, Error>, HttpDataCompletion) -> Bool)? = nil,
       onSend: ((HttpDataCompletion) -> Void)? = nil)
  {
    self.result = result
    self.onReceive = onReceive
    self.onSend = onSend
  }

  func api(_: Api, willSendRequest _: URLRequest, withId _: UUID, completion: HttpDataCompletion) -> Bool {
    if let onSend = onSend {
      onSend(completion)
    } else {
      completion?(result)
    }
    return true
  }

  func api(_: Api, didReceive result: Result<HttpDataResponse, Error>, withId _: UUID,
           for _: URLRequest, completion: HttpDataCompletion) -> Bool
  {
    onReceive?(result, completion) ?? false
  }
}
