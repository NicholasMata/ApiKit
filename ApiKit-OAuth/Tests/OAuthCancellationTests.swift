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

/// Holds refresh open until the test explicitly supplies a fresh credential.
private final class PendingTokenProvider: OAuthProvider {
  private let lock = NSLock()
  private let onRefresh: () -> Void
  private let completesSynchronously: Bool
  private var state: TokenState = .expired
  private var pendingRefresh: ((Result<String, Error>) -> Void)?
  private var count = 0

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
    lock.unlock()
    onRefresh()
    if completesSynchronously {
      finishRefresh()
    }
  }

  func finishRefresh(_ result: Result<String, Error> = .success("refreshed-token")) {
    lock.lock()
    if case let .success(token) = result {
      state = .valid(token: token)
    }
    let completion = pendingRefresh
    pendingRefresh = nil
    lock.unlock()
    completion?(result)
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
