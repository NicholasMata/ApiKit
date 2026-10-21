import Foundation

/// Recommended base for providers whose refresh responses contain credentials.
/// Fetching must not store credentials. Storage and clearing hooks run under the
/// same lock and must finish synchronously. Override every hook below.
///
/// Session events and refresh completions run outside the credential lock.
/// Do not call lifecycle methods from storage or token-state hooks.
open class SessionOAuthProvider<Credentials>: OAuthProvider, OAuthSessionEvents {
  private let lock = NSRecursiveLock()
  private let events = OAuthSessionEventPublisher()
  private var refreshId: UUID?
  private var completions: [(Result<String, Error>) -> Void] = []

  public init() {}

  public final var tokenState: TokenState {
    lock.lock()
    defer { lock.unlock() }
    return readTokenState()
  }

  /// Override to customize how the access token is attached to a request.
  open func attach(token: String, to request: URLRequest) -> URLRequest {
    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }

  public final func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription {
    events.subscribe(event, handler)
  }

  /// Concurrent callers share one fetch. After sign-out, a late fetch cannot store
  /// credentials or complete a later refresh attempt.
  public final func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
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
    refreshId = id
    completions = [completion]
    lock.unlock()
    fetchCredentials { [weak self] result in
      self?.finishRefresh(result, id: id)
    }
  }

  /// Clears local credentials synchronously and notifies all subscribers.
  /// Transport cancellation and server-side revocation are not implied.
  /// The same provider can serve a later sign-in after credentials are installed.
  public final func signOut() {
    lock.lock()
    refreshId = nil
    let completions = completions
    self.completions.removeAll()
    clearCredentials()
    lock.unlock()
    events.send(.signOut)
    for completion in completions {
      completion(.failure(OAuthError.sessionEnded))
    }
  }

  private func finishRefresh(_ result: Result<Credentials, Error>, id: UUID) {
    lock.lock()
    guard refreshId == id else {
      lock.unlock()
      return
    }
    refreshId = nil
    let completions = completions
    self.completions.removeAll()
    let tokenResult: Result<String, Error>
    do {
      let credentials = try result.get()
      let token = try accessToken(from: credentials)
      storeCredentials(credentials)
      tokenResult = .success(token)
    } catch {
      tokenResult = .failure(error)
    }
    lock.unlock()
    for completion in completions {
      completion(tokenResult)
    }
  }

  /// Read stored credentials and expiration. Runs under the credential lock.
  open func readTokenState() -> TokenState {
    fatalError("Override readTokenState()")
  }

  /// Fetch credentials without storing them, and complete with the original error on failure.
  open func fetchCredentials(completion _: @escaping (Result<Credentials, Error>) -> Void) {
    fatalError("Override fetchCredentials(completion:)")
  }

  /// Extract the access token, or throw if the response cannot supply one.
  open func accessToken(from _: Credentials) throws -> String {
    fatalError("Override accessToken(from:)")
  }

  /// Store credentials synchronously. Runs under the credential lock.
  open func storeCredentials(_: Credentials) {
    fatalError("Override storeCredentials(_:)")
  }

  /// Clear credentials synchronously. Runs under the credential lock.
  open func clearCredentials() {
    fatalError("Override clearCredentials()")
  }
}
