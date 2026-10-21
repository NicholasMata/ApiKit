import ApiKit
import ApiKit_OAuth
import XCTest

final class OAuthSessionTests: XCTestCase {
  func testSubscribersAreIndependentAndCancelOnRelease() {
    let events = OAuthSessionEventPublisher()
    var firstCount = 0
    var secondCount = 0
    let first = events.subscribe(.signOut) { firstCount += 1 }
    var second: OAuthSubscription? = events.subscribe(.signOut) { secondCount += 1 }
    events.send(.signOut)
    XCTAssertEqual(firstCount, 1)
    XCTAssertEqual(secondCount, 1)
    first.cancel()
    first.cancel()
    events.send(.signOut)
    XCTAssertEqual(firstCount, 1)
    XCTAssertEqual(secondCount, 2)
    XCTAssertNotNil(second)
    second = nil
    events.send(.signOut)
    XCTAssertEqual(secondCount, 2)
  }

  func testSubscriberCanUnsubscribeAndReadProviderDuringNotification() {
    let provider = SessionTestProvider()
    var subscription: OAuthSubscription?
    var count = 0
    subscription = provider.subscribe(.signOut) {
      XCTAssertEqual(provider.tokenState, .missing)
      count += 1
      subscription?.cancel()
    }
    provider.signOut()
    provider.signOut()
    XCTAssertEqual(count, 1)
  }

  func testConcurrentSubscriptionCancellationRunsUnregistrationOnce() {
    let lock = NSLock()
    var count = 0
    let subscription = OAuthSubscription {
      lock.lock()
      count += 1
      lock.unlock()
    }
    DispatchQueue.concurrentPerform(iterations: 50) { _ in subscription.cancel() }
    XCTAssertEqual(count, 1)
  }

  func testRefreshStoresBeforeCompletionAndIgnoresDuplicateCallbacks() {
    let provider = SessionTestProvider()
    var count = 0
    provider.refreshToken { result in
      XCTAssertEqual(try? result.get(), "fresh")
      XCTAssertEqual(provider.tokenState, .valid(token: "fresh"))
      count += 1
    }
    provider.finish(0, with: .success("fresh"))
    provider.finish(0, with: .success("duplicate"))
    XCTAssertEqual(provider.storedTokens, ["fresh"])
    XCTAssertEqual(count, 1)
  }

  func testConcurrentRefreshCallersShareFetchAndAllComplete() {
    let provider = SessionTestProvider()
    let completed = expectation(description: "Every refresh caller completes")
    completed.expectedFulfillmentCount = 40
    completed.assertForOverFulfill = true
    DispatchQueue.concurrentPerform(iterations: 40) { _ in
      provider.refreshToken { result in
        XCTAssertEqual(try? result.get(), "fresh")
        completed.fulfill()
      }
    }
    XCTAssertEqual(provider.fetchCount, 1)
    provider.finish(0, with: .success("fresh"))
    wait(for: [completed], timeout: 2)
    XCTAssertEqual(provider.storedTokens, ["fresh"])
  }

  func testSignOutSynchronouslyClearsAndRejectsLateRefresh() {
    let provider = SessionTestProvider()
    var completionCount = 0
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else {
        return XCTFail("Expected ended session, got \(result)")
      }
      completionCount += 1
    }
    provider.signOut()
    XCTAssertEqual(provider.tokenState, .missing)
    XCTAssertEqual(completionCount, 1)
    provider.finish(0, with: .success("stale"))
    provider.finish(0, with: .failure(URLError(.timedOut)))
    XCTAssertEqual(provider.tokenState, .missing)
    XCTAssertTrue(provider.storedTokens.isEmpty)
    XCTAssertEqual(completionCount, 1)
  }

  func testOldRefreshCannotCompleteNewSessionRefresh() {
    let provider = SessionTestProvider()
    provider.refreshToken { _ in }
    provider.signOut()
    provider.installExpiredSession()
    var newResult: Result<String, Error>?
    provider.refreshToken { newResult = $0 }
    provider.finish(0, with: .success("stale"))
    XCTAssertNil(newResult)
    XCTAssertTrue(provider.storedTokens.isEmpty)
    provider.finish(1, with: .success("new-session"))
    XCTAssertEqual(try? newResult?.get(), "new-session")
    XCTAssertEqual(provider.storedTokens, ["new-session"])
  }

  func testSignOutWaitsForCredentialStorageThenClearsIt() {
    let provider = SessionTestProvider()
    let storing = expectation(description: "Store hook entered")
    let releaseStore = DispatchSemaphore(value: 0)
    provider.onStore = {
      storing.fulfill()
      XCTAssertEqual(releaseStore.wait(timeout: .now() + 2), .success)
    }
    provider.refreshToken { _ in }
    let refreshFinished = expectation(description: "Refresh finishes")
    DispatchQueue.global().async {
      provider.finish(0, with: .success("fresh"))
      refreshFinished.fulfill()
    }
    wait(for: [storing], timeout: 2)
    let logoutStarted = DispatchSemaphore(value: 0)
    let logoutReturned = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      logoutStarted.signal()
      provider.signOut()
      logoutReturned.signal()
    }
    XCTAssertEqual(logoutStarted.wait(timeout: .now() + 2), .success)
    XCTAssertEqual(logoutReturned.wait(timeout: .now() + 0.05), .timedOut)
    releaseStore.signal()
    XCTAssertEqual(logoutReturned.wait(timeout: .now() + 2), .success)
    wait(for: [refreshFinished], timeout: 2)
    XCTAssertEqual(provider.tokenState, .missing)
  }

  func testFetchAndTokenExtractionErrorsAreForwardedWithoutStoring() {
    let provider = SessionTestProvider()
    provider.refreshToken { result in
      guard case let .failure(error) = result else { return XCTFail("Expected timeout") }
      XCTAssertEqual((error as? URLError)?.code, .timedOut)
    }
    provider.finish(0, with: .failure(URLError(.timedOut)))
    provider.refreshToken { result in
      guard case .failure(SessionTestError.invalidToken) = result else { return XCTFail("Expected extraction error") }
    }
    provider.finish(1, with: .success(""))
    XCTAssertTrue(provider.storedTokens.isEmpty)
  }

  func testMissingCredentialsDoNotStartFetch() {
    let provider = SessionTestProvider()
    provider.signOut()
    provider.refreshToken { result in
      guard case .failure(OAuthError.noToken) = result else { return XCTFail("Expected missing token") }
    }
    XCTAssertEqual(provider.fetchCount, 0)
  }

  func testSignOutNotifiesMultipleInterceptorsAndTheyCanServeNewSession() throws {
    let provider = SessionTestProvider()
    let refreshing = expectation(description: "Shared refresh starts")
    provider.onFetch = { refreshing.fulfill() }
    let failed = expectation(description: "Sign-out is not a renewal failure")
    failed.isInverted = true
    let first = OAuthInterceptor(provider: provider, onFailedToRenew: { _ in failed.fulfill() })
    let second = OAuthInterceptor(provider: provider, onFailedToRenew: { _ in failed.fulfill() })
    let api = Api()
    let request = try URLRequest(url: XCTUnwrap(URL(string: "https://apikit.test")))
    let cancelled = expectation(description: "Both interceptor requests cancel")
    cancelled.expectedFulfillmentCount = 2
    cancelled.assertForOverFulfill = true
    first.api(api, modifyRequest: request, withId: UUID()) {
      XCTAssertNil($0)
      cancelled.fulfill()
    }
    wait(for: [refreshing], timeout: 2)
    second.api(api, modifyRequest: request, withId: UUID()) {
      XCTAssertNil($0)
      cancelled.fulfill()
    }
    provider.signOut()
    wait(for: [cancelled], timeout: 2)
    provider.finish(0, with: .success("old-session"))
    XCTAssertEqual(provider.tokenState, .missing)

    provider.onFetch = nil
    provider.installExpiredSession()
    let newFetch = expectation(description: "New session starts a refresh")
    provider.onFetch = { newFetch.fulfill() }
    let resumed = expectation(description: "Same interceptor serves new session")
    first.api(api, modifyRequest: request, withId: UUID()) {
      XCTAssertEqual($0?.value(forHTTPHeaderField: "Authorization"), "Bearer new-session")
      resumed.fulfill()
    }
    wait(for: [newFetch], timeout: 2)
    provider.finish(1, with: .success("new-session"))
    wait(for: [resumed], timeout: 2)
    wait(for: [failed], timeout: 0.7)
  }

  func testCustomProviderCanPublishEventsWithoutInheritingBaseClass() throws {
    let provider = CustomEventProvider()
    let started = expectation(description: "Custom refresh starts")
    provider.onRefresh = { started.fulfill() }
    let released = expectation(description: "Interceptor releases despite outstanding provider callback")
    var oauth: OAuthInterceptor? = LifecycleInterceptor(provider: provider, onDeinit: { released.fulfill() })
    let cancelled = expectation(description: "Custom event cancels waiter")
    cancelled.assertForOverFulfill = true
    try oauth?.api(Api(), modifyRequest: URLRequest(url: XCTUnwrap(URL(string: "https://apikit.test"))), withId: UUID()) {
      XCTAssertNil($0)
      cancelled.fulfill()
    }
    wait(for: [started], timeout: 2)
    provider.signOut()
    wait(for: [cancelled], timeout: 2)
    // Its provider deliberately reports a late result: the interceptor ignores it.
    provider.finish?(.success("stale"))
    let drained = expectation(description: "Interceptor has processed late callback")
    try oauth?.api(Api(), modifyRequest: URLRequest(url: XCTUnwrap(URL(string: "https://apikit.test"))), withId: UUID()) { _ in
      drained.fulfill()
    }
    wait(for: [drained], timeout: 2)
    oauth = nil
    // The outstanding provider callback must not keep the interceptor alive.
    wait(for: [released], timeout: 2)
  }

  func testSignOutCompletesApiOperationWithoutWaitingForCustomRefreshCallback() throws {
    let provider = CustomEventProvider()
    let started = expectation(description: "Custom refresh starts")
    provider.onRefresh = { started.fulfill() }
    let responseQueue = OperationQueue()
    let api = Api(config: DefaultApiConfig(
      interceptors: [OAuthInterceptor(provider: provider)], responseQueue: responseQueue
    ))
    let completed = expectation(description: "API operation completes cancellation once")
    completed.assertForOverFulfill = true
    let request = try URLRequest(url: XCTUnwrap(URL(string: "https://apikit.test")))
    let operation = api.send(request) { (result: Result<HttpDataResponse, Error>) in
      guard case .failure(ApiError.cancelled) = result else { return XCTFail("Expected cancellation, got \(result)") }
      XCTAssertTrue(OperationQueue.current === responseQueue)
      completed.fulfill()
    }
    operation.onUrlSessionTask = { task in
      XCTFail("Signed-out request must not reach transport")
      task.cancel()
    }
    wait(for: [started], timeout: 2)
    provider.signOut()
    wait(for: [completed], timeout: 2)
    XCTAssertTrue(operation.isCancelled)
    XCTAssertTrue(operation.isFinished)
    // Transport finishes later, after the user has already received cancellation.
    provider.finish?(.success("stale"))
  }
}

private final class LifecycleInterceptor: OAuthInterceptor {
  private let onDeinit: () -> Void

  init(provider: OAuthProvider, onDeinit: @escaping () -> Void) {
    self.onDeinit = onDeinit
    super.init(provider: provider)
  }

  deinit { onDeinit() }
}

private enum SessionTestError: Error {
  case invalidToken
}

private final class SessionTestProvider: SessionOAuthProvider<String> {
  private let stateLock = NSLock()
  private var state: TokenState = .expired
  private var stored: [String] = []
  private let fetchLock = NSLock()
  private var callbacks: [(Result<String, Error>) -> Void] = []
  var onFetch: (() -> Void)?
  var onStore: (() -> Void)?

  var fetchCount: Int {
    fetchLock.lock()
    defer { fetchLock.unlock() }
    return callbacks.count
  }

  var storedTokens: [String] {
    stateLock.lock()
    defer { stateLock.unlock() }
    return stored
  }

  func installExpiredSession() {
    stateLock.lock()
    state = .expired
    stateLock.unlock()
  }

  override func readTokenState() -> TokenState {
    stateLock.lock()
    defer { stateLock.unlock() }
    return state
  }

  override func fetchCredentials(completion: @escaping (Result<String, Error>) -> Void) {
    fetchLock.lock()
    callbacks.append(completion)
    fetchLock.unlock()
    onFetch?()
  }

  func finish(_ index: Int, with result: Result<String, Error>) {
    fetchLock.lock()
    let callback = callbacks[index]
    fetchLock.unlock()
    callback(result)
  }

  override func accessToken(from credentials: String) throws -> String {
    guard !credentials.isEmpty else { throw SessionTestError.invalidToken }
    return credentials
  }

  override func storeCredentials(_ credentials: String) {
    onStore?()
    stateLock.lock()
    stored.append(credentials)
    state = .valid(token: credentials)
    stateLock.unlock()
  }

  override func clearCredentials() {
    stateLock.lock()
    state = .missing
    stateLock.unlock()
  }
}

/// Exercises the public protocols with no inheritance from SessionOAuthProvider.
private final class CustomEventProvider: OAuthProvider, OAuthSessionEvents {
  let events = OAuthSessionEventPublisher()
  private let lock = NSLock()
  private var state: TokenState = .expired
  var onRefresh: (() -> Void)?
  var finish: ((Result<String, Error>) -> Void)?

  var tokenState: TokenState {
    lock.lock()
    defer { lock.unlock() }
    return state
  }

  func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
    finish = completion
    onRefresh?()
  }

  func signOut() {
    lock.lock()
    state = .missing
    lock.unlock()
    events.send(.signOut)
  }

  func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription {
    events.subscribe(event, handler)
  }
}
