import Foundation

/// Recommended provider contract with default session and refresh coordination.
/// Implement the credential hooks and retain one stable coordinator per provider.
/// Fetching must not store credentials. The other hooks run under the coordinator's
/// lock and must finish synchronously without calling lifecycle methods.
public protocol SessionOAuthProvider: OAuthProvider, OAuthSessionEvents {
  associatedtype Credentials

  var session: OAuthSessionCoordinator<Credentials> { get }

  func readTokenState() -> TokenState
  func fetchCredentials(completion: @escaping (Result<Credentials, Error>) -> Void)
  func accessToken(from credentials: Credentials) throws -> String
  func storeCredentials(_ credentials: Credentials)
  func clearCredentials()
  /// Install credentials from an already completed authentication flow.
  func beginSession(with credentials: Credentials)
}

public extension SessionOAuthProvider {
  var tokenState: TokenState {
    session.tokenState(read: readTokenState)
  }

  func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription {
    session.subscribe(event, handler)
  }

  /// Installs credentials locally and invalidates refreshes from the previous session.
  /// Does not perform a sign-in request.
  func beginSession(with credentials: Credentials) {
    session.beginSession(with: credentials, store: storeCredentials, clear: clearCredentials)
  }

  /// Fetches without storing, then commits credentials only for the current session.
  func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
    session.refreshToken(
      readTokenState: readTokenState,
      fetchCredentials: fetchCredentials,
      commitCredentials: { [weak self] credentials in
        guard let self = self else { throw OAuthError.sessionEnded }
        let token = try self.accessToken(from: credentials)
        self.storeCredentials(credentials)
        return token
      },
      completion: completion
    )
  }

  /// Clears local credentials synchronously and invalidates outstanding refreshes.
  /// Does not perform server-side logout or token revocation.
  func endSession() {
    session.endSession(clear: clearCredentials)
  }
}

/// Stores the mutable coordination state used by `SessionOAuthProvider` defaults.
/// Events and refresh completions run outside the credential lock.
public final class OAuthSessionCoordinator<Credentials>: OAuthSessionEvents {
  private let lock = NSRecursiveLock()
  private let events = OAuthSessionEventPublisher()
  private var sessionId = UUID()
  private var refreshId: UUID?
  private var completions: [(Result<String, Error>) -> Void] = []

  public init() {}

  func tokenState(read: () -> TokenState) -> TokenState {
    lock.lock()
    defer { lock.unlock() }
    return read()
  }

  public func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription {
    events.subscribe(event, handler)
  }

  /// Installs login credentials synchronously and begins a new session. Pending
  /// refreshes from the previous session end with `OAuthError.sessionEnded`.
  func beginSession(with credentials: Credentials, store: (Credentials) -> Void, clear: () -> Void) {
    lock.lock()
    sessionId = UUID()
    refreshId = nil
    let completions = completions
    self.completions.removeAll()
    clear()
    store(credentials)
    lock.unlock()
    events.send(.sessionStarted)
    for completion in completions {
      completion(.failure(OAuthError.sessionEnded))
    }
  }

  /// Concurrent callers share one fetch. After the session ends, a late fetch cannot store
  /// credentials or complete a later refresh attempt.
  func refreshToken(
    readTokenState: () -> TokenState,
    fetchCredentials: (@escaping (Result<Credentials, Error>) -> Void) -> Void,
    commitCredentials: @escaping (Credentials) throws -> String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    lock.lock()
    if refreshId != nil {
      completions.append(completion)
      lock.unlock()
      return
    }
    guard readTokenState() != .missing else {
      lock.unlock()
      completion(.failure(OAuthError.noToken))
      return
    }
    let id = UUID()
    let session = sessionId
    refreshId = id
    completions = [completion]
    lock.unlock()
    fetchCredentials { [weak self] result in
      self?.finishRefresh(result, id: id, session: session, commitCredentials: commitCredentials)
    }
  }

  /// Clears local credentials synchronously and notifies all subscribers.
  /// Transport cancellation and server-side revocation are not implied.
  /// Use `beginSession(with:)` to install credentials for the next sign-in.
  func endSession(clear: () -> Void) {
    lock.lock()
    sessionId = UUID()
    refreshId = nil
    let completions = completions
    self.completions.removeAll()
    clear()
    lock.unlock()
    events.send(.sessionEnded)
    for completion in completions {
      completion(.failure(OAuthError.sessionEnded))
    }
  }

  private func finishRefresh(
    _ result: Result<Credentials, Error>, id: UUID, session: UUID,
    commitCredentials: (Credentials) throws -> String
  ) {
    lock.lock()
    guard sessionId == session, refreshId == id else {
      lock.unlock()
      return
    }
    refreshId = nil
    let completions = completions
    self.completions.removeAll()
    let tokenResult: Result<String, Error>
    do {
      let credentials = try result.get()
      let token = try commitCredentials(credentials)
      tokenResult = .success(token)
    } catch {
      tokenResult = .failure(error)
    }
    lock.unlock()
    for completion in completions {
      // Claim each delivery separately. An earlier callback may change sessions.
      // Callbacks whose delivery has begun cannot be withdrawn.
      lock.lock()
      let current = sessionId == session
      lock.unlock()
      completion(current ? tokenResult : .failure(OAuthError.sessionEnded))
    }
  }
}
