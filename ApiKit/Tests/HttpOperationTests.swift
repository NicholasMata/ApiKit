@testable import ApiKit
import XCTest

final class HttpOperationTests: XCTestCase {
  private let request = URLRequest(url: URL(string: "https://apikit.test/request")!)

  private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResponseURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  func testOperationWithoutHooksDeliversRawResponse() {
    let session = makeSession()
    defer { session.invalidateAndCancel() }
    let completed = expectation(description: "Raw response delivered")
    let operation = HttpOperation(request: request, session: session) { result in
      switch result {
      case let .success(response):
        // Status validation belongs to Api, not the operation.
        XCTAssertEqual(response.response.statusCode, 503)
        XCTAssertEqual(response.data, Data("response".utf8))
      case let .failure(error):
        XCTFail("Unexpected error: \(error)")
      }
      completed.fulfill()
    }
    operation.start()
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testApiAppliesBadStatusPolicyThroughResponseHook() {
    let session = makeSession()
    defer { session.invalidateAndCancel() }
    let queue = OperationQueue()
    let interceptor = ResponseQueueInterceptor(queue: queue)
    let api = Api(urlSession: session, config: DefaultApiConfig(interceptors: [interceptor], responseQueue: queue))
    let completed = expectation(description: "Bad status rejected")
    api.send(request) { result in
      XCTAssertTrue(OperationQueue.current === queue)
      guard case let .failure(ApiError.badStatusCode(_, response)) = result else {
        XCTFail("Expected badStatusCode, got \(result)")
        completed.fulfill()
        return
      }
      XCTAssertEqual(response.response.statusCode, 503)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(interceptor.receivedResponse)
  }

  func testApiSchedulesEarlyResponseAndCompletionOnResponseQueue() {
    let queue = OperationQueue()
    let interceptor = ResponseQueueInterceptor(queue: queue, suppliesEarlyResponse: true)
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor], responseQueue: queue))
    let completed = expectation(description: "Early response completes on configured queue")
    api.send(request) { result in
      XCTAssertTrue(OperationQueue.current === queue)
      guard case .failure(ApiError.notHttpRequest) = result else {
        XCTFail("Expected early response, got \(result)")
        completed.fulfill()
        return
      }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(interceptor.receivedResponse)
  }

  func testApiSkipsQueuedResponseHookAfterCancellation() {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.isSuspended = true
    defer { queue.isSuspended = false }
    let interceptor = ResponseQueueInterceptor(queue: queue, suppliesEarlyResponse: true)
    let supplied = expectation(description: "Early response queued")
    interceptor.onEarlyResponse = { supplied.fulfill() }
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor], responseQueue: queue))
    let completed = expectation(description: "Cancellation completes on configured queue")
    completed.assertForOverFulfill = true
    let operation = api.send(request) { result in
      XCTAssertTrue(OperationQueue.current === queue)
      guard case .failure(ApiError.cancelled) = result else {
        XCTFail("Expected cancellation, got \(result)")
        completed.fulfill()
        return
      }
      completed.fulfill()
    }
    wait(for: [supplied], timeout: 2)
    operation.cancel()
    queue.isSuspended = false
    wait(for: [completed], timeout: 2)
    XCTAssertFalse(interceptor.receivedResponse)
  }

  func testHooksRunInOrderAndCompleteOnlyOnce() {
    let completed = expectation(description: "Hooks deliver one result")
    completed.assertForOverFulfill = true
    var stages: [String] = []
    let operation = HttpOperation(request: request) { result in
      guard case .failure(ApiError.notHttpRequest) = result else {
        XCTFail("Expected response hook result")
        completed.fulfill()
        return
      }
      completed.fulfill()
    }
    let id = operation.id
    operation.requestModifiers = [
      { request, identifier, proceed in
        XCTAssertEqual(identifier, id)
        stages.append("first modifier")
        var request = request
        request.setValue("modified", forHTTPHeaderField: "X-Test")
        proceed(request)
      },
      { request, identifier, proceed in
        XCTAssertEqual(identifier, id)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "modified")
        stages.append("second modifier")
        proceed(request)
      },
    ]
    operation.onWillSendRequest = { request, identifier, complete in
      XCTAssertEqual(identifier, id)
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "modified")
      stages.append("before send")
      complete(.failure(URLError(.timedOut)))
      return true
    }
    operation.onReceiveResponse = { result, request, identifier, complete in
      XCTAssertEqual(identifier, id)
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), "modified")
      guard case let .failure(error as URLError) = result else {
        XCTFail("Expected transport error")
        complete(result)
        return
      }
      XCTAssertEqual(error.code, .timedOut)
      stages.append("response")
      complete(.failure(ApiError.notHttpRequest))
      complete(.failure(URLError(.badURL)))
    }
    operation.onUrlSessionTask = { _ in XCTFail("Early response should avoid creating a task") }
    operation.start()
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(stages, ["first modifier", "second modifier", "before send", "response"])
    XCTAssertTrue(operation.isFinished)
  }

  func testCancelWhileResponseHookIsPendingIgnoresLateCompletion() {
    let processing = expectation(description: "Response hook is pending")
    let completed = expectation(description: "Cancellation completes once")
    completed.assertForOverFulfill = true
    let operation = HttpOperation(request: request) { result in
      guard case .failure(ApiError.cancelled) = result else {
        XCTFail("Expected cancellation, got \(result)")
        completed.fulfill()
        return
      }
      completed.fulfill()
    }
    var pendingCompletion: HttpDataCompletion = nil
    operation.onWillSendRequest = { _, _, complete in
      complete(.failure(ApiError.notHttpRequest))
      return true
    }
    operation.onReceiveResponse = { _, _, _, complete in
      pendingCompletion = complete
      processing.fulfill()
    }
    operation.start()
    wait(for: [processing], timeout: 2)
    XCTAssertTrue(operation.isExecuting)
    XCTAssertNotNil(pendingCompletion)
    operation.cancel()
    pendingCompletion?(.failure(ApiError.notHttpRequest))
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testStartReturnsWhileRequestModifierIsPending() {
    let modifying = expectation(description: "Modifier is waiting for asynchronous work")
    let returned = expectation(description: "Start returns before modification completes")
    let completed = expectation(description: "Continuation completes the request")
    let operation = HttpOperation(request: request) { _ in completed.fulfill() }
    var pending: ((URLRequest?) -> Void)?
    operation.requestModifiers = [{ _, _, proceed in
      pending = proceed
      modifying.fulfill()
    }]
    operation.onWillSendRequest = { _, _, complete in
      complete(.failure(ApiError.notHttpRequest))
      return true
    }
    DispatchQueue(label: "HttpOperationTests.start").async {
      operation.start()
      returned.fulfill()
    }
    wait(for: [modifying, returned], timeout: 2)
    XCTAssertTrue(operation.isExecuting)
    XCTAssertFalse(operation.isFinished)
    pending?(request)
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testSerialQueueWaitsForAsynchronousOperationToFinish() {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let modifying = expectation(description: "First request waits for its modifier")
    let completed = expectation(description: "Both operations complete")
    completed.expectedFulfillmentCount = 2
    var pending: ((URLRequest?) -> Void)?
    let first = HttpOperation(request: request) { _ in completed.fulfill() }
    first.requestModifiers = [{ _, _, proceed in
      pending = proceed
      modifying.fulfill()
    }]
    first.onWillSendRequest = { _, _, complete in
      complete(.failure(ApiError.notHttpRequest))
      return true
    }
    let second = HttpOperation(request: request) { _ in completed.fulfill() }
    second.onWillSendRequest = { _, _, complete in
      XCTAssertTrue(first.isFinished)
      complete(.failure(ApiError.notHttpRequest))
      return true
    }
    queue.addOperation(first)
    wait(for: [modifying], timeout: 2)
    queue.addOperation(second)
    XCTAssertTrue(first.isExecuting)
    XCTAssertFalse(second.isExecuting)
    XCTAssertFalse(second.isFinished)
    pending?(request)
    wait(for: [completed], timeout: 2)
  }

  func testDependenciesWaitForAsynchronousOperationToFinish() {
    let queue = OperationQueue()
    queue.isSuspended = true
    let modifying = expectation(description: "Request waits for its modifier")
    let completed = expectation(description: "Dependent operation runs")
    let prerequisite = BlockOperation {}
    let operation = HttpOperation(request: request, completion: nil)
    var pending: ((URLRequest?) -> Void)?
    operation.addDependency(prerequisite)
    operation.requestModifiers = [{ _, _, proceed in
      XCTAssertTrue(prerequisite.isFinished)
      pending = proceed
      modifying.fulfill()
    }]
    operation.onWillSendRequest = { _, _, complete in
      complete(.failure(ApiError.notHttpRequest))
      return true
    }
    let dependent = BlockOperation {
      XCTAssertTrue(operation.isFinished)
      completed.fulfill()
    }
    dependent.addDependency(operation)
    queue.addOperations([dependent, operation, prerequisite], waitUntilFinished: false)
    queue.isSuspended = false

    wait(for: [modifying], timeout: 2)
    XCTAssertFalse(operation.isFinished)
    XCTAssertFalse(dependent.isExecuting)
    XCTAssertFalse(dependent.isFinished)
    pending?(request)
    wait(for: [completed], timeout: 2)
  }

  func testRepeatedModifierCallbackCannotSkipNextModifier() {
    let modifying = expectation(description: "Second modifier is pending")
    let completed = expectation(description: "Request completes once")
    completed.assertForOverFulfill = true
    let operation = HttpOperation(request: request) { _ in completed.fulfill() }
    var pending: ((URLRequest?) -> Void)?
    operation.requestModifiers = [
      { request, _, proceed in
        proceed(request)
        proceed(request)
      },
      { _, _, proceed in
        pending = proceed
        modifying.fulfill()
      },
    ]
    operation.onWillSendRequest = { request, _, complete in
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Second-Modifier"), "finished")
      complete(.failure(ApiError.notHttpRequest))
      return true
    }
    operation.start()
    wait(for: [modifying], timeout: 2)
    var modified = request
    modified.setValue("finished", forHTTPHeaderField: "X-Second-Modifier")
    pending?(modified)
    wait(for: [completed], timeout: 2)
  }
}

private final class ResponseQueueInterceptor: ApiInterceptor {
  let queue: OperationQueue
  let suppliesEarlyResponse: Bool
  var receivedResponse = false
  var onEarlyResponse: (() -> Void)?

  init(queue: OperationQueue, suppliesEarlyResponse: Bool = false) {
    self.queue = queue
    self.suppliesEarlyResponse = suppliesEarlyResponse
  }

  func api(_: Api, willSendRequest _: URLRequest, withId _: UUID, completion: HttpDataCompletion) -> Bool {
    guard suppliesEarlyResponse else { return false }
    completion?(.failure(ApiError.notHttpRequest))
    onEarlyResponse?()
    return true
  }

  func api(_: Api, didReceive _: Result<HttpDataResponse, Error>, withId _: UUID,
           for _: URLRequest, completion _: HttpDataCompletion) -> Bool
  {
    XCTAssertTrue(OperationQueue.current === queue)
    receivedResponse = true
    return false
  }
}

private final class ResponseURLProtocol: URLProtocol {
  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: 503,
                                   httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("response".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
