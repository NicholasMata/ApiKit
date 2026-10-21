import Foundation

public enum OAuthSessionEvent: Hashable {
  /// The provider ended its local authentication session.
  case signOut
  /// New login credentials replaced the previous authentication session.
  case sessionStarted
}

/// Optional session notifications supported by `OAuthInterceptor`.
public protocol OAuthSessionEvents: AnyObject {
  /// Registers an independent listener. Retain the returned token to stay subscribed.
  /// Handlers run synchronously on the publishing thread. Cancellation does not
  /// retract callbacks captured by an event already being published.
  func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription
}

/// Cancels its subscription when explicitly cancelled or released.
public final class OAuthSubscription {
  private let lock = NSLock()
  private var cancellation: (() -> Void)?

  /// Custom event sources can supply their own unregistration action.
  public init(cancel: @escaping () -> Void) {
    cancellation = cancel
  }

  public func cancel() {
    lock.lock()
    let cancellation = cancellation
    self.cancellation = nil
    lock.unlock()
    cancellation?()
  }

  deinit {
    cancel()
  }
}

/// A reusable event source for custom providers. Supports multiple subscribers.
/// Events are delivered outside the publisher's lock; delivery order is unspecified.
public final class OAuthSessionEventPublisher: OAuthSessionEvents {
  private let lock = NSLock()
  private var handlers: [OAuthSessionEvent: [UUID: () -> Void]] = [:]

  public init() {}

  public func subscribe(_ event: OAuthSessionEvent, _ handler: @escaping () -> Void) -> OAuthSubscription {
    let id = UUID()
    lock.lock()
    handlers[event, default: [:]][id] = handler
    lock.unlock()
    return OAuthSubscription { [weak self] in
      guard let self = self else { return }
      self.lock.lock()
      self.handlers[event]?[id] = nil
      self.lock.unlock()
    }
  }

  public func send(_ event: OAuthSessionEvent) {
    lock.lock()
    let callbacks = handlers[event].map { Array($0.values) } ?? []
    lock.unlock()
    for callback in callbacks {
      callback()
    }
  }
}
