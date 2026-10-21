import ApiKit
import ApiKit_OAuth
import XCTest

final class OAuthSessionTests: XCTestCase {
  func testProtocolDefaultsDispatchThroughOAuthProvider() {
    let concrete = SessionTestProvider()
    let provider: OAuthProvider = concrete
    let events: OAuthSessionEvents = concrete
    var endSessions = 0
    let subscription = events.subscribe(.sessionEnded) { endSessions += 1 }
    concrete.beginSession(with: "login")
    XCTAssertEqual(provider.tokenState, .valid(token: "login"))
    provider.endSession()
    XCTAssertEqual(provider.tokenState, .missing)
    XCTAssertEqual(endSessions, 1)
    withExtendedLifetime(subscription) {}
  }

  func testStoredFetchCallbackDoesNotRetainProvider() throws {
    let released = expectation(description: "Provider releases despite retained fetch callback")
    var provider: SessionTestProvider? = SessionTestProvider()
    provider?.onDeinit = { released.fulfill() }
    provider?.refreshToken { _ in }
    let callback = try XCTUnwrap(provider?.fetchCallback(0))
    provider = nil
    wait(for: [released], timeout: 2)
    callback(.success("late"))
  }

  func testLogoutDuringCallbackDeliveryRejectsRemainingRefreshResults() {
    assertSessionChangeDuringDelivery { $0.endSession() }
  }

  func testNewLoginDuringCallbackDeliveryRejectsRemainingRefreshResults() {
    assertSessionChangeDuringDelivery { $0.beginSession(with: "new-login") }
  }

  private func assertSessionChangeDuringDelivery(_ change: (SessionTestProvider) -> Void) {
    let provider = SessionTestProvider()
    let delivering = expectation(description: "First callback begins delivery")
    let release = DispatchSemaphore(value: 0)
    provider.refreshToken { result in
      XCTAssertEqual(try? result.get(), "fresh")
      delivering.fulfill()
      XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
    }
    let cancelled = expectation(description: "Second callback rejects old session result")
    cancelled.assertForOverFulfill = true
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else {
        return XCTFail("Expected ended session, got \(result)")
      }
      cancelled.fulfill()
    }
    let finished = expectation(description: "Delivery finishes")
    DispatchQueue.global().async {
      provider.finish(0, with: .success("fresh"))
      finished.fulfill()
    }
    wait(for: [delivering], timeout: 2)
    change(provider)
    release.signal()
    wait(for: [cancelled, finished], timeout: 2)
  }

  func testBeginSessionInstallsCredentialsAndRejectsOldFetch() {
    let provider = SessionTestProvider()
    var ended = 0
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else { return XCTFail("Expected ended session") }
      ended += 1
    }
    var started = 0
    var endSessions = 0
    let startedSubscription = provider.subscribe(.sessionStarted) {
      XCTAssertEqual(provider.tokenState, .valid(token: "login"))
      started += 1
    }
    let endSessionSubscription = provider.subscribe(.sessionEnded) { endSessions += 1 }
    provider.beginSession(with: "login")
    provider.finish(0, with: .success("old-refresh"))
    XCTAssertEqual(provider.tokenState, .valid(token: "login"))
    XCTAssertEqual(provider.storedTokens, ["login"])
    XCTAssertEqual(ended, 1)
    XCTAssertEqual(started, 1)
    XCTAssertEqual(endSessions, 0)
    withExtendedLifetime([startedSubscription, endSessionSubscription]) {}
  }

  func testStartingNewSessionCancelsOldInterceptorWaiterAndAllowsNewRequests() throws {
    let provider = SessionTestProvider()
    let refreshing = expectation(description: "Old refresh starts")
    provider.onFetch = { refreshing.fulfill() }
    let oauth = OAuthInterceptor(provider: provider)
    let request = try URLRequest(url: XCTUnwrap(URL(string: "https://apikit.test")))
    let cancelled = expectation(description: "Old-session request cancels")
    oauth.api(Api(), modifyRequest: request, withId: UUID()) {
      XCTAssertNil($0)
      cancelled.fulfill()
    }
    wait(for: [refreshing], timeout: 2)
    provider.beginSession(with: "new-login")
    wait(for: [cancelled], timeout: 2)
    provider.finish(0, with: .success("old-token"))
    let resumed = expectation(description: "New request uses login credentials")
    oauth.api(Api(), modifyRequest: request, withId: UUID()) {
      XCTAssertEqual($0?.value(forHTTPHeaderField: "Authorization"), "Bearer new-login")
      resumed.fulfill()
    }
    wait(for: [resumed], timeout: 2)
    XCTAssertEqual(provider.storedTokens, ["new-login"])
    XCTAssertEqual(provider.fetchCount, 1)
  }

  func testSubscribersAreIndependentAndCancelOnRelease() {
    let events = OAuthSessionEventPublisher()
    var firstCount = 0
    var secondCount = 0
    let first = events.subscribe(.sessionEnded) { firstCount += 1 }
    var second: OAuthSubscription? = events.subscribe(.sessionEnded) { secondCount += 1 }
    events.send(.sessionEnded)
    XCTAssertEqual(firstCount, 1)
    XCTAssertEqual(secondCount, 1)
    first.cancel()
    first.cancel()
    events.send(.sessionEnded)
    XCTAssertEqual(firstCount, 1)
    XCTAssertEqual(secondCount, 2)
    XCTAssertNotNil(second)
    second = nil
    events.send(.sessionEnded)
    XCTAssertEqual(secondCount, 2)
  }

  func testSubscriberCanUnsubscribeAndReadProviderDuringNotification() {
    let provider = SessionTestProvider()
    var subscription: OAuthSubscription?
    var count = 0
    subscription = provider.subscribe(.sessionEnded) {
      XCTAssertEqual(provider.tokenState, .missing)
      count += 1
      subscription?.cancel()
    }
    provider.endSession()
    provider.endSession()
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

  func testEndSessionSynchronouslyClearsAndRejectsLateRefresh() {
    let provider = SessionTestProvider()
    var completionCount = 0
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else {
        return XCTFail("Expected ended session, got \(result)")
      }
      completionCount += 1
    }
    provider.endSession()
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
    provider.endSession()
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

  func testEndSessionWaitsForCredentialStorageThenClearsIt() {
    assertEndSessionWaitsForStore { provider in
      provider.refreshToken { _ in }
      provider.finish(0, with: .success("fresh"))
    }
  }

  func testEndSessionWaitsForLoginStorageThenClearsIt() {
    assertEndSessionWaitsForStore { $0.beginSession(with: "login") }
  }

  private func assertEndSessionWaitsForStore(_ store: @escaping (SessionTestProvider) -> Void) {
    let provider = SessionTestProvider()
    let storing = expectation(description: "Store hook entered")
    let releaseStore = DispatchSemaphore(value: 0)
    provider.onStore = {
      storing.fulfill()
      XCTAssertEqual(releaseStore.wait(timeout: .now() + 2), .success)
    }
    let refreshFinished = expectation(description: "Refresh finishes")
    DispatchQueue.global().async {
      store(provider)
      refreshFinished.fulfill()
    }
    wait(for: [storing], timeout: 2)
    let logoutStarted = DispatchSemaphore(value: 0)
    let logoutReturned = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
      logoutStarted.signal()
      provider.endSession()
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
    provider.endSession()
    provider.refreshToken { result in
      guard case .failure(OAuthError.noToken) = result else { return XCTFail("Expected missing token") }
    }
    XCTAssertEqual(provider.fetchCount, 0)
  }

  func testEndSessionNotifiesMultipleInterceptorsAndTheyCanServeNewSession() throws {
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
    provider.endSession()
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
    provider.endSession()
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

  func testEndSessionCompletesApiOperationWithoutWaitingForCustomRefreshCallback() throws {
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
    provider.endSession()
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

private final class SessionTestProvider: SessionOAuthProvider {
  let session = OAuthSessionCoordinator<String>()
  private let stateLock = NSLock()
  private var state: TokenState = .expired
  private var stored: [String] = []
  private let fetchLock = NSLock()
  private var callbacks: [(Result<String, Error>) -> Void] = []
  var onFetch: (() -> Void)?
  var onStore: (() -> Void)?
  var onDeinit: (() -> Void)?

  deinit { onDeinit?() }

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

  func readTokenState() -> TokenState {
    stateLock.lock()
    defer { stateLock.unlock() }
    return state
  }

  func fetchCredentials(completion: @escaping (Result<String, Error>) -> Void) {
    fetchLock.lock()
    callbacks.append(completion)
    fetchLock.unlock()
    onFetch?()
  }

  func fetchCallback(_ index: Int) -> (Result<String, Error>) -> Void {
    fetchLock.lock()
    defer { fetchLock.unlock() }
    return callbacks[index]
  }

  func finish(_ index: Int, with result: Result<String, Error>) {
    fetchCallback(index)(result)
  }

  func accessToken(from credentials: String) throws -> String {
    guard !credentials.isEmpty else { throw SessionTestError.invalidToken }
    return credentials
  }

  func storeCredentials(_ credentials: String) {
    onStore?()
    stateLock.lock()
    stored.append(credentials)
    state = .valid(token: credentials)
    stateLock.unlock()
  }

  func clearCredentials() {
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

  func endSession() {
    lock.lock()
    state = .missing
    lock.unlock()
    events.send(.sessionEnded)
  }

  func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription {
    events.subscribe(event, handler)
  }
}
