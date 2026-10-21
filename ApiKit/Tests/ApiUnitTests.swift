@testable import ApiKit
import XCTest

final class ApiUnitTests: XCTestCase {
  private let request = URLRequest(url: URL(string: "https://apikit.test/request")!)

  private func assertCancelled(_ result: Result<HttpDataResponse, Error>,
                               file: StaticString = #filePath, line: UInt = #line)
  {
    guard case let .failure(error) = result,
          case ApiError.cancelled = error
    else {
      XCTFail("Expected ApiError.cancelled, got \(result)", file: file, line: line)
      return
    }
  }

  func testCancelBeforeRequestStarts() {
    let queue = OperationQueue()
    queue.isSuspended = true
    defer { queue.isSuspended = false }
    let api = Api(config: DefaultApiConfig(requestQueue: queue))
    let completed = expectation(description: "Cancellation completes once")
    completed.assertForOverFulfill = true
    var cancellationId: UUID?
    let operation = api.send(request) { result in
      self.assertCancelled(result)
      if case let .failure(ApiError.cancelled(_, id)) = result {
        cancellationId = id
      }
      completed.fulfill()
    }
    let finished = expectation(description: "Queue finishes cancelled operation")
    operation.completionBlock = { finished.fulfill() }

    operation.cancel()
    operation.cancel()

    wait(for: [completed], timeout: 2)
    XCTAssertEqual(cancellationId, operation.id)
    XCTAssertTrue(operation.isCancelled)
    XCTAssertFalse(operation.isExecuting)
    queue.isSuspended = false
    wait(for: [finished], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testCancelDuringRequestModificationUnblocksQueue() {
    let interceptor = PendingInterceptor()
    let modifying = expectation(description: "Interceptor is modifying request")
    interceptor.onModify = { modifying.fulfill() }
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor], requestQueue: queue))
    let completed = expectation(description: "Cancelled completion")
    completed.assertForOverFulfill = true
    let operation = api.send(request) { result in
      self.assertCancelled(result)
      completed.fulfill()
    }
    wait(for: [modifying], timeout: 2)
    XCTAssertTrue(operation.isExecuting)
    XCTAssertFalse(operation.isFinished)
    operation.cancel()

    let queueUnblocked = expectation(description: "Request queue is unblocked")
    queue.addOperation { queueUnblocked.fulfill() }
    wait(for: [completed, queueUnblocked], timeout: 2)
    interceptor.pendingModification?(request)
    XCTAssertTrue(operation.isFinished)
  }

  func testInterceptorCanCancelRequest() {
    let interceptor = PendingInterceptor()
    interceptor.onModify = { [weak interceptor] in interceptor?.pendingModification?(nil) }
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor]))
    let completed = expectation(description: "Interceptor cancellation completes")
    let operation = api.send(request) { result in
      self.assertCancelled(result)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isCancelled)
    XCTAssertTrue(operation.isFinished)
  }

  func testCancelInterceptedResponseIgnoresLateCompletion() {
    let interceptor = PendingInterceptor()
    let intercepted = expectation(description: "Response intercepted")
    interceptor.onSend = { intercepted.fulfill() }
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor]))
    let completed = expectation(description: "Completion is called once")
    completed.assertForOverFulfill = true
    let operation = api.send(request) { result in
      self.assertCancelled(result)
      completed.fulfill()
    }
    wait(for: [intercepted], timeout: 2)
    operation.cancel()
    interceptor.pendingResponse?(.failure(ApiError.notHttpRequest))
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testCancelRunningRequestStopsNetworkTask() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PendingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer {
      session.invalidateAndCancel()
      PendingURLProtocol.onStart = nil
      PendingURLProtocol.onStop = nil
    }
    let started = expectation(description: "Network request started")
    let stopped = expectation(description: "Network request stopped")
    PendingURLProtocol.onStart = { started.fulfill() }
    PendingURLProtocol.onStop = { stopped.fulfill() }
    let completed = expectation(description: "Cancelled completion")
    completed.assertForOverFulfill = true
    let api = Api(urlSession: session)
    let operation = api.send(request) { result in
      self.assertCancelled(result)
      completed.fulfill()
    }
    wait(for: [started], timeout: 2)
    operation.cancel()
    wait(for: [completed, stopped], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testSuccessfulOperationFinishesAndReleasesSerialQueue() throws {
    let interceptor = PendingInterceptor()
    interceptor.response = try .success(HttpDataResponse(
      response: XCTUnwrap(try HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)),
      data: Data()
    ))
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor], requestQueue: queue))
    let completed = expectation(description: "Both requests complete")
    completed.expectedFulfillmentCount = 2
    let completion: HttpDataCompletion = { result in
      if case let .failure(error) = result {
        XCTFail("Unexpected error: \(error)")
      }
      completed.fulfill()
    }
    let first = api.send(request, completion: completion)
    let second = api.send(request, completion: completion)
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(first.isFinished)
    XCTAssertTrue(second.isFinished)
    XCTAssertNotEqual(first.id, second.id)
    first.cancel()
    XCTAssertFalse(first.isCancelled)
  }

  @available(iOS 13.0, *)
  func testAsyncCancellationCompletesWhileInterceptorIsPending() async {
    await assertAsyncCancellation { api, request in
      let _: HttpDataResponse = try await api.send(request)
    }
  }

  @available(iOS 13.0, *)
  func testAsyncDecodedResponseCancellation() async {
    await assertAsyncCancellation { api, request in
      let _: HttpResponse<String> = try await api.send(request)
    }
  }

  @available(iOS 13.0, *)
  func testAsyncDecodedBodyCancellation() async {
    await assertAsyncCancellation { api, request in
      let _: String = try await api.send(request)
    }
  }

  @available(iOS 13.0, *)
  func testAsyncDownloadCancellation() async {
    await assertAsyncCancellation { api, request in
      _ = try await api.download(request, asFileName: "cancelled-download")
    }
  }

  @available(iOS 13.0, *)
  private func assertAsyncCancellation(_ send: @escaping (Api, URLRequest) async throws -> Void) async {
    let interceptor = PendingInterceptor()
    let modifying = expectation(description: "Interceptor pending")
    interceptor.onModify = { modifying.fulfill() }
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor]))
    let completed = expectation(description: "Async cancellation returns")
    let task = Task {
      do {
        try await send(api, request)
        XCTFail("Expected cancellation")
      } catch {
        guard case ApiError.cancelled = error else {
          XCTFail("Unexpected error: \(error)")
          completed.fulfill()
          return
        }
      }
      completed.fulfill()
    }
    await fulfillment(of: [modifying], timeout: 2)
    task.cancel()
    await fulfillment(of: [completed], timeout: 2)
  }

  @available(iOS 13.0, *)
  func testAlreadyCancelledSwiftTaskDoesNotEnqueueRequest() async {
    let queue = OperationQueue()
    queue.isSuspended = true
    defer { queue.isSuspended = false }
    let api = Api(config: DefaultApiConfig(requestQueue: queue))
    let completed = expectation(description: "Already cancelled task returns")
    Task {
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        let _: HttpDataResponse = try await api.send(request)
        XCTFail("Expected CancellationError")
      } catch {
        XCTAssertTrue(error is CancellationError)
      }
      completed.fulfill()
    }
    await fulfillment(of: [completed], timeout: 2)
    XCTAssertEqual(queue.operationCount, 0)
  }

  func testCancellationBeforeAsyncOperationRegistration() {
    let cancellation = HttpOperationCancellation()
    let completed = expectation(description: "Registered operation cancelled")
    let operation = HttpOperation(request: request) { result in
      self.assertCancelled(result)
      completed.fulfill()
    }
    operation.onWillSendRequest = { _, _, _ in
      XCTFail("Cancelled operation should not start")
      return true
    }
    cancellation.cancel()
    cancellation.register(operation)
    operation.start()
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testCancelWhilePreparingNetworkTaskPreventsSending() {
    let preparing = expectation(description: "Request preparation started")
    let returned = expectation(description: "Operation start returned")
    let completed = expectation(description: "Cancellation completed")
    let allowSending = DispatchSemaphore(value: 0)
    let operation = HttpOperation(request: request) { result in
      self.assertCancelled(result)
      completed.fulfill()
    }
    operation.onWillSendRequest = { _, _, _ in
      preparing.fulfill()
      allowSending.wait()
      return false
    }
    operation.onUrlSessionTask = { _ in XCTFail("Cancelled request should not create a task") }
    DispatchQueue.global().async {
      operation.start()
      returned.fulfill()
    }
    wait(for: [preparing], timeout: 2)
    operation.cancel()
    allowSending.signal()
    wait(for: [completed, returned], timeout: 2)
    XCTAssertTrue(operation.isFinished)
  }

  func testCancelFromTaskNotificationCancelsRegisteredTask() {
    let completed = expectation(description: "Cancellation completed")
    let operation = HttpOperation(request: request) { result in
      self.assertCancelled(result)
      completed.fulfill()
    }
    var createdTask: URLSessionTask?
    operation.onUrlSessionTask = { [weak operation] task in
      createdTask = task
      operation?.cancel()
    }
    operation.start()
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isFinished)
    XCTAssertNotNil(createdTask)
    XCTAssertTrue(createdTask?.state == .canceling || createdTask?.state == .completed)
  }

  func testOperationIdMatchesInterceptorCallbacks() {
    let interceptor = PendingInterceptor()
    interceptor.response = .failure(ApiError.notHttpRequest)
    let api = Api(config: DefaultApiConfig(interceptors: [interceptor]))
    let completed = expectation(description: "Intercepted request completes")
    let operation = api.send(request) { _ in completed.fulfill() }

    wait(for: [completed], timeout: 2)
    XCTAssertEqual(interceptor.modificationIds, [operation.id])
    XCTAssertEqual(interceptor.sendingIds, [operation.id])
    XCTAssertEqual(interceptor.responseIds, [operation.id])
  }
}

private final class PendingInterceptor: ApiInterceptor {
  var onModify: (() -> Void)?
  var onSend: (() -> Void)?
  var pendingModification: ((URLRequest?) -> Void)?
  var pendingResponse: HttpDataCompletion = nil
  var response: Result<HttpDataResponse, Error>?
  var modificationIds: [UUID] = []
  var sendingIds: [UUID] = []
  var responseIds: [UUID] = []

  func api(_: Api, modifyRequest request: URLRequest, withId identifier: UUID,
           onNewRequest: @escaping (URLRequest?) -> Void)
  {
    modificationIds.append(identifier)
    pendingModification = onNewRequest
    if let onModify = onModify {
      onModify()
    } else {
      onNewRequest(request)
    }
  }

  func api(_: Api, willSendRequest _: URLRequest, withId identifier: UUID,
           completion: HttpDataCompletion) -> Bool
  {
    sendingIds.append(identifier)
    pendingResponse = completion
    onSend?()
    if let response = response {
      completion?(response)
    }
    return true
  }

  func api(_: Api, didReceive _: Result<HttpDataResponse, Error>, withId identifier: UUID,
           for _: URLRequest, completion _: HttpDataCompletion) -> Bool
  {
    responseIds.append(identifier)
    return false
  }
}

private final class PendingURLProtocol: URLProtocol {
  static var onStart: (() -> Void)?
  static var onStop: (() -> Void)?

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.onStart?()
  }

  override func stopLoading() {
    Self.onStop?()
  }
}
