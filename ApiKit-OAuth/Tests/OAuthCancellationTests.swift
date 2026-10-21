import ApiKit
import ApiKit_OAuth
import XCTest

final class OAuthCancellationTests: XCTestCase {
  func testCancellingRefreshInitiatorDoesNotCancelRefreshForWaitingRequest() {
    let refreshing = expectation(description: "A starts token refresh")
    let waiting = expectation(description: "B returns from OAuth while refresh is pending")
    let provider = PendingTokenProvider(onRefresh: { refreshing.fulfill() })
    defer { provider.finishRefresh() }
    let oauth = ObservedOAuthInterceptor(provider: provider, onReturn: { path in
      if path == "/b" {
        waiting.fulfill()
      }
    })
    let responses = SuccessfulResponseInterceptor()
    let api = Api(config: DefaultApiConfig(interceptors: [oauth, responses]))
    let cancelled = expectation(description: "A completes cancellation before refresh finishes")
    cancelled.assertForOverFulfill = true
    let first = api.send(request("/a")) { (result: Result<HttpDataResponse, Error>) in
      self.assertCancelled(result)
      cancelled.fulfill()
    }
    wait(for: [refreshing], timeout: 2)

    let succeeded = expectation(description: "B completes with the refreshed token")
    succeeded.assertForOverFulfill = true
    let second = api.send(request("/b")) { (result: Result<HttpDataResponse, Error>) in
      self.assertSuccessful(result)
      succeeded.fulfill()
    }
    wait(for: [waiting], timeout: 2)
    first.cancel()
    wait(for: [cancelled], timeout: 2)

    XCTAssertTrue(first.isFinished)
    XCTAssertTrue(provider.isRefreshPending)
    XCTAssertEqual(provider.refreshCount, 1)
    XCTAssertTrue(oauth.hasReturned(from: "/b"))
    XCTAssertFalse(second.isFinished)
    XCTAssertTrue(responses.requests.isEmpty)

    provider.finishRefresh()
    wait(for: [succeeded], timeout: 2)

    XCTAssertTrue(second.isFinished)
    XCTAssertEqual(provider.refreshCount, 1)
    XCTAssertEqual(responses.requests.map { $0.url?.path }, ["/b"])
    XCTAssertEqual(responses.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-token")
  }

  func testCancellingWaitingRequestPreservesRefreshWithoutBlockingOAuthInvocation() {
    let refreshing = expectation(description: "A starts token refresh")
    let waiting = expectation(description: "B's OAuth invocation returns before refresh finishes")
    let provider = PendingTokenProvider(onRefresh: { refreshing.fulfill() })
    defer { provider.finishRefresh() }
    let oauth = ObservedOAuthInterceptor(provider: provider, onReturn: { path in
      if path == "/b" {
        waiting.fulfill()
      }
    })
    let responses = SuccessfulResponseInterceptor()
    let api = Api(config: DefaultApiConfig(interceptors: [oauth, responses]))
    let succeeded = expectation(description: "A completes after refresh")
    let first = api.send(request("/a")) { (result: Result<HttpDataResponse, Error>) in
      self.assertSuccessful(result)
      succeeded.fulfill()
    }
    wait(for: [refreshing], timeout: 2)

    let cancelled = expectation(description: "B completes cancellation while refresh is pending")
    cancelled.assertForOverFulfill = true
    let second = api.send(request("/b")) { (result: Result<HttpDataResponse, Error>) in
      self.assertCancelled(result)
      cancelled.fulfill()
    }
    wait(for: [waiting], timeout: 2)
    second.cancel()
    wait(for: [cancelled], timeout: 2)

    // OAuth has returned and stored a continuation; no invocation is blocked on refresh.
    XCTAssertTrue(second.isFinished)
    XCTAssertTrue(oauth.hasReturned(from: "/b"))
    XCTAssertTrue(provider.isRefreshPending)
    XCTAssertFalse(first.isFinished)
    XCTAssertTrue(responses.requests.isEmpty)

    provider.finishRefresh()
    wait(for: [succeeded], timeout: 2)
    XCTAssertTrue(oauth.hasReturned(from: "/b"))

    let reused = expectation(description: "A future request reuses the refreshed token")
    api.send(request("/c")) { (result: Result<HttpDataResponse, Error>) in
      self.assertSuccessful(result)
      reused.fulfill()
    }
    wait(for: [reused], timeout: 2)

    XCTAssertEqual(provider.refreshCount, 1)
    XCTAssertEqual(Set(responses.requests.compactMap { $0.url?.path }), ["/a", "/c"])
    XCTAssertTrue(responses.requests.allSatisfy {
      $0.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token"
    })
  }

  func testManyRequestsShareRefreshAndReturnBeforeItFinishes() {
    let count = 40
    let refreshing = expectation(description: "One shared refresh starts")
    refreshing.assertForOverFulfill = true
    let returned = expectation(description: "All OAuth invocations return before refresh")
    returned.expectedFulfillmentCount = count
    let provider = PendingTokenProvider(onRefresh: { refreshing.fulfill() })
    defer { provider.finishRefresh() }
    let oauth = ObservedOAuthInterceptor(provider: provider, onReturn: { _ in returned.fulfill() })
    let responses = SuccessfulResponseInterceptor()
    let api = Api(config: DefaultApiConfig(interceptors: [oauth, responses]))
    let completed = expectation(description: "All requests finish after refresh")
    completed.expectedFulfillmentCount = count
    completed.assertForOverFulfill = true
    let operations = (0 ..< count).map { index in
      api.send(request("/\(index)")) { (result: Result<HttpDataResponse, Error>) in
        self.assertSuccessful(result)
        completed.fulfill()
      }
    }
    wait(for: [refreshing, returned], timeout: 2)
    XCTAssertTrue(provider.isRefreshPending)
    XCTAssertEqual(provider.refreshCount, 1)
    XCTAssertTrue(responses.requests.isEmpty)
    XCTAssertTrue(operations.allSatisfy { $0.isExecuting && !$0.isFinished })

    provider.finishRefresh()
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(responses.requests.count, count)
    XCTAssertEqual(provider.refreshCount, 1)
  }

  func testRefreshFailureResolvesAllWaitingRequestsOnce() {
    let refreshing = expectation(description: "Refresh starts")
    let waiting = expectation(description: "B queues behind refresh")
    let failed = expectation(description: "Shared refresh failure is reported once")
    failed.assertForOverFulfill = true
    let provider = PendingTokenProvider(onRefresh: { refreshing.fulfill() })
    defer { provider.finishRefresh() }
    let oauth = ObservedOAuthInterceptor(provider: provider, onReturn: { path in
      if path == "/b" {
        waiting.fulfill()
      }
    }, onFailedToRenew: { error in
      XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
      failed.fulfill()
    })
    let responses = SuccessfulResponseInterceptor()
    let api = Api(config: DefaultApiConfig(interceptors: [oauth, responses]))
    let cancelled = expectation(description: "Both waiting requests complete once")
    cancelled.expectedFulfillmentCount = 2
    cancelled.assertForOverFulfill = true
    api.send(request("/a")) { (result: Result<HttpDataResponse, Error>) in
      self.assertCancelled(result)
      cancelled.fulfill()
    }
    wait(for: [refreshing], timeout: 2)
    api.send(request("/b")) { (result: Result<HttpDataResponse, Error>) in
      self.assertCancelled(result)
      cancelled.fulfill()
    }
    wait(for: [waiting], timeout: 2)
    provider.finishRefresh(.failure(URLError(.cannotConnectToHost)))
    wait(for: [cancelled, failed], timeout: 2)
    XCTAssertEqual(provider.refreshCount, 1)
    XCTAssertTrue(responses.requests.isEmpty)
  }

  func testSynchronousRefreshAndSerialRequestQueueDoNotDeadlock() {
    let provider = PendingTokenProvider(onRefresh: {}, completesSynchronously: true)
    let responses = SuccessfulResponseInterceptor()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let api = Api(config: DefaultApiConfig(
      interceptors: [OAuthInterceptor(provider: provider), responses], requestQueue: queue
    ))
    let completed = expectation(description: "Both serial requests complete")
    completed.expectedFulfillmentCount = 2
    for path in ["/a", "/b"] {
      api.send(request(path)) { (result: Result<HttpDataResponse, Error>) in
        self.assertSuccessful(result)
        completed.fulfill()
      }
    }
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(provider.refreshCount, 1)
    XCTAssertEqual(responses.requests.map { $0.url?.path }, ["/a", "/b"])
  }

  func testCancellingEveryWaiterDoesNotSendRequestsAfterRefresh() {
    let count = 20
    let refreshing = expectation(description: "Shared refresh starts")
    let returned = expectation(description: "All modifier calls return")
    returned.expectedFulfillmentCount = count
    let provider = PendingTokenProvider(onRefresh: { refreshing.fulfill() })
    defer { provider.finishRefresh() }
    let oauth = ObservedOAuthInterceptor(provider: provider, onReturn: { path in
      if path != "/future" { returned.fulfill() }
    })
    let responses = SuccessfulResponseInterceptor()
    let api = Api(config: DefaultApiConfig(interceptors: [oauth, responses]))
    let cancelled = expectation(description: "All requests cancel once")
    cancelled.expectedFulfillmentCount = count
    cancelled.assertForOverFulfill = true
    let operations = (0 ..< count).map { index in
      api.send(request("/\(index)")) { result in
        self.assertCancelled(result)
        cancelled.fulfill()
      }
    }
    wait(for: [refreshing, returned], timeout: 5)
    operations.forEach { $0.cancel() }
    wait(for: [cancelled], timeout: 5)
    XCTAssertTrue(provider.isRefreshPending)
    provider.finishRefresh()

    // The same OAuth queue processes this after draining the cancelled waiters.
    let reused = expectation(description: "Future request reuses refreshed token")
    api.send(request("/future")) { result in
      self.assertSuccessful(result)
      reused.fulfill()
    }
    wait(for: [reused], timeout: 5)
    XCTAssertEqual(provider.refreshCount, 1)
    XCTAssertEqual(responses.requests.map { $0.url?.path }, ["/future"])
  }

  func testRefreshCanBeRetriedAfterFailure() {
    let refreshing = expectation(description: "Refresh starts")
    let provider = PendingTokenProvider(onRefresh: { refreshing.fulfill() })
    let responses = SuccessfulResponseInterceptor()
    let api = Api(config: DefaultApiConfig(interceptors: [OAuthInterceptor(provider: provider), responses]))
    let cancelled = expectation(description: "Failed refresh cancels first request")
    api.send(request("/first")) { result in
      self.assertCancelled(result)
      cancelled.fulfill()
    }
    wait(for: [refreshing], timeout: 5)
    provider.finishRefresh(.failure(URLError(.timedOut)))
    wait(for: [cancelled], timeout: 5)

    let retried = expectation(description: "Another refresh starts")
    provider.onNextRefresh = { retried.fulfill() }
    let succeeded = expectation(description: "Retry succeeds")
    api.send(request("/retry")) { result in
      self.assertSuccessful(result)
      succeeded.fulfill()
    }
    wait(for: [retried], timeout: 5)
    provider.finishRefresh()
    wait(for: [succeeded], timeout: 5)
    XCTAssertEqual(provider.refreshCount, 2)
    XCTAssertEqual(responses.requests.map { $0.url?.path }, ["/retry"])
  }

  func testDuplicateRefreshCompletionDoesNotCompleteRequestsTwice() {
    let refreshing = expectation(description: "Refresh starts")
    let provider = PendingTokenProvider(onRefresh: { refreshing.fulfill() })
    let api = Api(config: DefaultApiConfig(interceptors: [OAuthInterceptor(provider: provider), SuccessfulResponseInterceptor()]))
    let completed = expectation(description: "One request completion")
    completed.assertForOverFulfill = true
    api.send(request("/first")) { result in
      self.assertSuccessful(result)
      completed.fulfill()
    }
    wait(for: [refreshing], timeout: 5)
    provider.finishRefresh(repeatCompletion: true)
    wait(for: [completed], timeout: 5)
    let drained = expectation(description: "Later request passes duplicate callback")
    api.send(request("/later")) { result in
      self.assertSuccessful(result)
      drained.fulfill()
    }
    wait(for: [drained], timeout: 5)
    XCTAssertEqual(provider.refreshCount, 1)
  }

  func testMissingTokenCancelsAndReportsFailureOnMainThread() {
    let provider = FixedTokenProvider(state: .missing)
    let failed = expectation(description: "Missing token is reported")
    failed.assertForOverFulfill = true
    let oauth = OAuthInterceptor(provider: provider, onFailedToRenew: { error in
      XCTAssertTrue(Thread.isMainThread)
      if case OAuthError.noToken? = error {} else { XCTFail("Expected noToken") }
      failed.fulfill()
    })
    let cancelled = expectation(description: "Missing token cancels request")
    oauth.api(Api(), modifyRequest: request("/missing"), withId: UUID()) { newRequest in
      XCTAssertNil(newRequest)
      cancelled.fulfill()
    }
    wait(for: [cancelled, failed], timeout: 5)
  }

  func testValidTokenUsesProviderAttachmentWithoutRefreshing() {
    let provider = FixedTokenProvider(state: .valid(token: "existing"))
    let oauth = OAuthInterceptor(provider: provider)
    let attached = expectation(description: "Provider attaches valid token")
    oauth.api(Api(), modifyRequest: request("/valid"), withId: UUID()) { newRequest in
      XCTAssertEqual(newRequest?.value(forHTTPHeaderField: "X-Custom-Auth"), "existing")
      XCTAssertNil(newRequest?.value(forHTTPHeaderField: "Authorization"))
      attached.fulfill()
    }
    wait(for: [attached], timeout: 5)
  }

  private func request(_ path: String) -> URLRequest {
    URLRequest(url: URL(string: "https://apikit.test\(path)")!)
  }

  private func assertCancelled(_ result: Result<HttpDataResponse, Error>,
                               file: StaticString = #filePath, line: UInt = #line)
  {
    guard case .failure(ApiError.cancelled) = result else {
      XCTFail("Expected cancellation, got \(result)", file: file, line: line)
      return
    }
  }

  private func assertSuccessful(_ result: Result<HttpDataResponse, Error>,
                                file: StaticString = #filePath, line: UInt = #line)
  {
    if case let .failure(error) = result {
      XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
  }
}

private final class FixedTokenProvider: OAuthProvider {
  func signOut() {}
  let tokenState: TokenState
  init(state: TokenState) { tokenState = state }
  func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
    XCTFail("Valid and missing states must not refresh")
    completion(.failure(OAuthError.noToken))
  }
  func attach(token: String, to request: URLRequest) -> URLRequest {
    var request = request
    request.setValue(token, forHTTPHeaderField: "X-Custom-Auth")
    return request
  }
}

/// Holds refresh open until the test explicitly supplies a fresh credential.
private final class PendingTokenProvider: OAuthProvider {
  func signOut() {
    lock.lock()
    state = .missing
    let completion = pendingRefresh
    pendingRefresh = nil
    lock.unlock()
    completion?(.failure(OAuthError.sessionEnded))
  }
  private let lock = NSLock()
  private let onRefresh: () -> Void
  private let completesSynchronously: Bool
  private var state: TokenState = .expired
  private var pendingRefresh: ((Result<String, Error>) -> Void)?
  private var count = 0
  private var nextRefresh: (() -> Void)?

  var onNextRefresh: (() -> Void)? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return nextRefresh
    }
    set {
      lock.lock()
      nextRefresh = newValue
      lock.unlock()
    }
  }

  init(onRefresh: @escaping () -> Void, completesSynchronously: Bool = false) {
    self.onRefresh = onRefresh
    self.completesSynchronously = completesSynchronously
  }

  var tokenState: TokenState {
    lock.lock()
    defer { lock.unlock() }
    return state
  }

  var refreshCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  var isRefreshPending: Bool {
    lock.lock()
    defer { lock.unlock() }
    return pendingRefresh != nil
  }

  func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
    lock.lock()
    count += 1
    pendingRefresh = completion
    let next = nextRefresh
    nextRefresh = nil
    lock.unlock()
    if let next = next { next() } else { onRefresh() }
    if completesSynchronously {
      finishRefresh()
    }
  }

  func finishRefresh(_ result: Result<String, Error> = .success("refreshed-token"), repeatCompletion: Bool = false) {
    lock.lock()
    if case let .success(token) = result {
      state = .valid(token: token)
    }
    let completion = pendingRefresh
    pendingRefresh = nil
    lock.unlock()
    completion?(result)
    if repeatCompletion { completion?(result) }
  }
}

/// Observes the real OAuth implementation without replacing its synchronization.
private final class ObservedOAuthInterceptor: ApiInterceptor {
  private let oauth: OAuthInterceptor
  private let onEnter: (String) -> Void
  private let onReturn: (String) -> Void
  private let lock = NSLock()
  private var returnedPaths: Set<String> = []

  init(provider: OAuthProvider, onEnter: @escaping (String) -> Void = { _ in },
       onReturn: @escaping (String) -> Void = { _ in },
       onFailedToRenew: ((Error?) -> Void)? = nil)
  {
    oauth = OAuthInterceptor(provider: provider, onFailedToRenew: onFailedToRenew)
    self.onEnter = onEnter
    self.onReturn = onReturn
  }

  func hasReturned(from path: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return returnedPaths.contains(path)
  }

  func api(_ api: Api, modifyRequest request: URLRequest, withId identifier: UUID,
           onNewRequest: @escaping (URLRequest?) -> Void)
  {
    let path = request.url?.path ?? ""
    onEnter(path)
    oauth.api(api, modifyRequest: request, withId: identifier, onNewRequest: onNewRequest)
    lock.lock()
    returnedPaths.insert(path)
    lock.unlock()
    onReturn(path)
  }
}

/// Supplies a successful response only after a request reaches the send stage.
private final class SuccessfulResponseInterceptor: ApiInterceptor {
  private let lock = NSLock()
  private var sentRequests: [URLRequest] = []

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return sentRequests
  }

  func api(_: Api, willSendRequest request: URLRequest, withId _: UUID,
           completion: HttpDataCompletion) -> Bool
  {
    lock.lock()
    sentRequests.append(request)
    lock.unlock()
    guard let url = request.url,
          let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    else {
      completion?(.failure(ApiError.notHttpRequest))
      return true
    }
    completion?(.success(HttpDataResponse(response: response, data: Data())))
    return true
  }
}
