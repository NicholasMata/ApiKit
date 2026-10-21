# Managing Sessions

Install credentials, end a local session, and observe lifecycle changes.

## Overview

Keep the same provider instance in the application and its interceptor:

```swift
let oauth = OAuthInterceptor(provider: provider)
let api = Api(config: DefaultApiConfig(interceptors: [oauth]))
```

For a provider conforming to ``SessionOAuthProvider``, install the response from
a successful login through the provider:

```swift
provider.beginSession(with: credentials)
```

This does not perform authentication. It clears the previous credentials, stores
the new response under coordination, changes the session identity, and publishes
`.sessionStarted`. Requests waiting on the old session cancel; subsequent
requests can use the new credentials.

Use it after every new login or account switch, even when the same user logs in
again. It is unnecessary for ordinary token refresh or application startup with
persisted credentials. A new coordinator already has a fresh identity, and
`readTokenState()` reads the existing store.

## End the Local Session

```swift
provider.endSession()
```

The recommended defaults synchronously invalidate outstanding refresh attempts
and clear credentials, then publish `.sessionEnded`. Waiting interceptor requests
complete asynchronously with `ApiError.cancelled`. Direct pending refresh callers
receive `OAuthError.sessionEnded`. Late fetch results cannot write old credentials.

Ending a session does not revoke tokens at the server, end an identity provider's
browser session, or cancel an independent refresh transport. Requests already
past OAuth require cancellation through their operations.

## Observe Events

```swift
let subscription = provider.subscribe(.sessionEnded) {
    DispatchQueue.main.async {
        // Update application UI.
    }
}

// Later, when this listener is no longer needed:
subscription.cancel()
```

Each call registers an independent subscriber. Retain the ``OAuthSubscription``
to remain subscribed; explicitly cancelling or releasing it unregisters the
listener. Use weak captures when a listener would otherwise retain its owner.

Events run synchronously on the publishing thread, outside the credential lock.
Subscriber order is unspecified. Cancellation does not retract callbacks already
captured by an in-progress publication. Events have no state snapshot; if
transitions occur concurrently, read `provider.tokenState` for current state.

Interceptors subscribe automatically to both `.sessionStarted` and `.sessionEnded`.
Applications do not need a second interceptor lifecycle call, and the same
interceptor can serve a later authentication session.

## Handle Refresh Failure

`onFailedToRenew` receives the provider's original refresh error on the main
queue after a short debounce. A normal ApiKit refresh timeout forwarded by the
provider arrives as `URLError(.timedOut)`. Missing credentials report
`OAuthError.noToken`. Ending a session is not itself a renewal failure.

```swift
oauth.onFailedToRenew = { error in
    if let error = error as? URLError, error.code == .timedOut {
        // Preserve credentials and allow a later retry.
        return
    }

    // Apply your authentication server's policy for this error.
}
```

A non-timeout error does not automatically mean the session is unusable.
Classify authentication-server rejection separately from temporary network
failures. The interceptor does not automatically end the session on refresh failure.

## Callback Delivery

Concurrent refresh callers share one fetch. Before each result callback's
delivery is claimed, the coordinator checks whether its session is still current.
An earlier callback may end or replace the session; remaining callbacks then
receive `OAuthError.sessionEnded`. A callback whose delivery has already begun
cannot be withdrawn.

Asynchronous providers must call their fetch completion on success or failure.
The coordinator has no independent timeout for arbitrary provider work. Network
refreshes made through ApiKit use their `URLSession` timeout behavior.
