# Migrating Providers

Move a custom provider to coordinated credential storage without changing its endpoint.

## Overview

Existing providers implementing ``OAuthProvider`` now need `endSession()`.
There is no default on that basic protocol because the library cannot know how
to clear arbitrary storage or stop a custom refresh from restoring it.

For recommended defaults, change the conformance to ``SessionOAuthProvider`` and
add a stored coordinator typed to your full decoded response:

```swift
final class MyOAuthProvider: SessionOAuthProvider {
    typealias Credentials = MyTokenResponse
    let session = OAuthSessionCoordinator<MyTokenResponse>()

    // Implement readTokenState, fetchCredentials, accessToken,
    // storeCredentials, and clearCredentials.
}
```

The class remains application-owned. It does not inherit a library base class or
construct a provider from initializer closures. The compiler requires all five
credential hooks.

## Split Fetching From Storage

Move the old `tokenState` getter's logic into `readTokenState()`.
Replace a refresh implementation that fetched, stored, and returned a string with
`fetchCredentials(completion:)`, returning `Result<MyTokenResponse, Error>`.
Forward networking and decoding failures unchanged.

Move the storage write into `storeCredentials(_:)` and token extraction into
`accessToken(from:)`. The default `refreshToken(completion:)` coordinates these
steps. Fetching must not write credentials before its completion.

## Update Login and Session Ending

Replace a direct write after login:

```swift
// Before: store.save(loginResponse)
provider.beginSession(with: loginResponse)
```

Use `provider.endSession()` instead of clearing the store directly. Implement
`clearCredentials()` with the synchronous storage-clearing portion of the old
logout path. Keep navigation and other UI effects outside that hook because
beginning a new session also clears the old credentials before installing new ones.

Keep the concrete provider available to application login code; the basic
`OAuthProvider` interface does not declare the typed `beginSession(with:)` method.
Persisted credentials on startup do not require reinstalling the login response.

## Keep API Configuration

Your authenticated API and interceptor order can remain the same. Reuse an open
API for the refresh request, or use `Api.send` if `Api.default` does not contain
the same OAuth interceptor. No additional API instance is required.

Methods previously called `startSession(with:)` and `signOut()` during development
are now `beginSession(with:)` and `endSession()`. The event formerly named
`.signOut` is `.sessionEnded`; `.sessionStarted` remains the session-begin event.

## Fully Custom Providers

Implement ``OAuthProvider`` and ``OAuthSessionEvents`` directly to own the entire
lifecycle. ``OAuthSessionEventPublisher`` supplies subscriber management:

```swift
private let events = OAuthSessionEventPublisher()

func subscribe(
    _ event: OAuthSessionEvent,
    _ handler: @escaping () -> Void
) -> OAuthSubscription {
    events.subscribe(event, handler)
}
```

Publish `.sessionEnded` after invalidating refresh work and clearing credentials,
before `endSession()` returns. Publish `.sessionStarted` when replacing a session.
Publish outside credential locks. Interceptors consume these events automatically,
but the custom provider still owns atomic storage and stale-result rejection.

A provider implementing only the basic protocol remains usable, but without
events the interceptor cannot cancel pending requests immediately when the local
session ends. It must wait for the provider's refresh completion.
