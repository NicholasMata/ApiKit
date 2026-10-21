# Using Google Authentication

Connect an application's Google Sign-In session to authenticated ApiKit requests.

## Overview

Add the `ApiKit-Google` product to your target. Configure the Google Sign-In SDK
for your application's client and platform, then complete initial sign-in or
restoration using that SDK. ApiKit does not present a Google sign-in screen.

Keep an explicit provider when the application needs to end the session:

```swift
import ApiKit
import ApiKit_OAuth
import ApiKit_Google

let provider = DefaultGoogleAuthProvider()
let oauth = OAuthInterceptor(provider: provider)
let api = Api(config: DefaultApiConfig(interceptors: [oauth]))
```

The provider uses `GIDSignIn.sharedInstance` by default. Its token state is missing
when no Google user exists, expired when that user's access token needs renewal,
or valid with the current access token. Normal requests use the OAuth interceptor
to wait for refresh when necessary.

## End the Local Session

```swift
provider.endSession()
```

This calls the SDK's local `signOut()`, publishes `.sessionEnded`, and resolves
pending refresh callers with `OAuthError.sessionEnded`. The interceptor cancels
requests waiting on that session. Token revocation is separate; ending the local
session does not call the SDK's disconnect/revocation operation.

Use the application's SDK sign-in flow to establish a later Google session. The
same provider and interceptor can serve requests afterward. The typed
`beginSession(with:)` method belongs to the separate `SessionOAuthProvider`
protocol, whose defaults manage application-defined credential storage.

## Refresh Boundaries

Refresh uses the existing user's authentication object rather than
`restorePreviousSignIn`. Late or duplicate callbacks cannot complete a cancelled
provider refresh, and a result for a replaced Google user is rejected.

ApiKit coordinates the work initiated through this provider. Google SDK sign-in,
restoration, or other operations started elsewhere in the application remain
application-owned. Requests already past OAuth need cancellation through their
own operations.

## Convenience Interceptor

``DefaultGoogleAuthInterceptor`` creates its own default Google provider:

```swift
let api = Api(config: DefaultApiConfig(
    interceptors: [DefaultGoogleAuthInterceptor()]
))
```

Prefer the explicit provider setup above when application code needs the provider's
session-ending method. Refresh failures use the original SDK error and reach the
OAuth interceptor's `onFailedToRenew` callback; apply your application's recovery
policy there rather than treating every transient error as an ended session.
