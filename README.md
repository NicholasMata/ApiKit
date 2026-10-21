# ApiKit

[![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)](#installation)
[![Tests](https://github.com/NicholasMata/ApiKit/actions/workflows/tests.yml/badge.svg?branch=1.1.0)](https://github.com/NicholasMata/ApiKit/actions/workflows/tests.yml?query=branch%3A1.1.0)

A simple way to connect your swift code to your APIs.

This branch targets **1.1.0**. See the [release notes](RELEASE_NOTES.md) for
cancellation fixes and execution changes. Development for **2.0.0** continues
on [`next`](https://github.com/NicholasMata/ApiKit/tree/next).

See [Testing](docs/TESTING.md) for local checks, CI jobs, and coverage reports.

### iOS 12+
```swift
Api.send(.get("https://jsonplaceholder.typicode.com/users")) { (result: Result<[User], Error>) in
    switch result {
        case let .success(users):
            break
        case let .failure(error):
            break
    }
}
```
### iOS 13+
```swift
let users: [User] = try await Api.send(.get("https://jsonplaceholder.typicode.com/users"))
```

## Cancellation

Keep the returned operation to cancel a request or download:

```swift
let operation = Api.send(.get("https://jsonplaceholder.typicode.com/users")) {
    (result: Result<[User], Error>) in
    // Cancellation completes once with ApiError.cancelled.
}
operation?.cancel()
```

Each operation exposes a read-only `id` (`UUID`) matching the identifier passed
to interceptor callbacks and included in `ApiError.cancelled`. Use it to
correlate an operation with those events.

Cancellation works while queued, waiting for an interceptor, or sending the
request. It stops the underlying URLSession task and finishes the operation.
Async requests and downloads also cancel their operation when the enclosing
Swift `Task` is cancelled. An already cancelled task throws `CancellationError`
before starting a request; cancelling an active request throws `ApiError.cancelled`.

Request preparation uses internal dispatch queues and callback continuations.
Waiting for an asynchronous request modifier or OAuth token refresh does not
block a thread. `requestQueue` starts and limits concurrent operations;
response interceptors and final completions run on `responseQueue`.

Requests sharing an `OAuthInterceptor` share an in-progress token refresh.
Cancelling one request leaves the refresh available to other requests. A failed
refresh cancels all requests waiting for that attempt.

## OAuth sessions

`OAuthProvider` requires `endSession()` without a default implementation. Custom
providers must implement it to clear local credentials and prevent outstanding
refreshes from restoring them. This is a source-breaking requirement for existing
providers. `OAuthTokenManagedProvider` implementations must also supply it; a token
manager's `clear()` alone is insufficient if it is asynchronous or a refresh can
subsequently write credentials again.

For the recommended implementation, conform to `SessionOAuthProvider`. Supply one
stored `OAuthSessionCoordinator` and implement the credential hooks. The compiler
requires every hook; no base class, initializer closures, or runtime traps are needed:

```swift
// MyTokenResponse, MyTokenStore, and MyTokenService are application-defined types.
final class MyOAuthProvider: SessionOAuthProvider {
    typealias Credentials = MyTokenResponse

    let session = OAuthSessionCoordinator<MyTokenResponse>()
    private let store: MyTokenStore
    private let tokenService: MyTokenService

    init(store: MyTokenStore, tokenService: MyTokenService) {
        self.store = store
        self.tokenService = tokenService
    }

    func readTokenState() -> TokenState {
        store.tokenState
    }

    func fetchCredentials(
        completion: @escaping (Result<MyTokenResponse, Error>) -> Void
    ) {
        tokenService.refresh(completion: completion) // Fetch only; do not store.
    }

    func accessToken(from credentials: MyTokenResponse) -> String {
        credentials.accessToken
    }

    func storeCredentials(_ credentials: MyTokenResponse) {
        store.save(credentials)
    }

    func clearCredentials() {
        store.clear()
    }
}
```

The protocol defaults coordinate storage with login and logout, reject stale or
duplicate refresh responses, and share concurrent refreshes. Install a successful login with
`provider.beginSession(with: credentials)`. This clears previous credentials, stores
the new response synchronously, invalidates previous refresh attempts, and publishes
`.sessionStarted`. Interceptors cancel old-session waiters and remain usable for
new requests. A refresh updates credentials within its existing session.

`beginSession(with:)` installs credentials after authentication has already succeeded;
it does not perform a sign-in request. `endSession()` ends the local session and
does not imply server-side logout or token revocation.

Keep the same coordinator for the provider's lifetime; do not create a new one in
a computed `session` getter. Default implementations are replaceable, so custom
implementations take responsibility for preserving their coordination guarantees.

Network fetching runs outside the credential lock. Storage, clearing, token-state,
and token-extraction hooks run under that lock and must finish synchronously
without calling lifecycle methods. Keep them short and avoid synchronous dispatch
to another queue that may be waiting for the provider. Storage read directly by
the fetch service or other application code must provide its own synchronization.
Use an API without the same OAuth interceptor for refresh requests to avoid waiting
on their own refresh. Implement `attach(token:to:)` to customize the default
Authorization bearer header.

The provider also implements the optional `OAuthSessionEvents` protocol. Interceptors
subscribe automatically and cancel waiting requests when the provider signs out.
Consumers can independently subscribe as well:

```swift
let provider = MyOAuthProvider(store: store, tokenService: tokenService)
let oauth = OAuthInterceptor(provider: provider)
let api = Api(config: DefaultApiConfig(interceptors: [oauth]))

let subscription = provider.subscribe(.sessionEnded) {
    // Update application state. Runs on the thread that publishes the event.
}

provider.beginSession(with: credentials)
provider.endSession()
subscription.cancel()
```

Retain each subscription to keep it active. Explicit cancellation or releasing the
token unregisters that subscriber. Multiple interceptors and application listeners
can observe one provider. Use `beginSession(with:)` for subsequent sign-ins with
the same managed provider and interceptor. Events carry no state snapshot: if
transitions happen concurrently, read `provider.tokenState` for current state.

Fully custom providers can implement both `OAuthProvider` and `OAuthSessionEvents`
without using the managed provider. `OAuthSessionEventPublisher` supplies thread-safe
subscription management: forward `subscribe` to it and call `send(.sessionEnded)` after
invalidating refresh work and clearing credentials, before `endSession()` returns.
Publish `.sessionStarted` when replacing a session with new login credentials.
Publish outside credential locks. Plain `OAuthProvider` implementations remain usable,
but without events the interceptor cannot cancel its waiting requests immediately on logout.

Ending the local session does not revoke tokens at the server or cancel refresh transport.
Requests already past OAuth must be cancelled through their operations. Requests
still waiting for OAuth are cancelled asynchronously on each interceptor's queue
with `ApiError.cancelled`; late refresh results from the old session are ignored.
Direct refresh callers receive `OAuthError.sessionEnded` if ending the session cancels their
pending refresh. Session identity is checked separately before each refresh callback
begins delivery; an earlier callback may sign out or begin a new session. A callback
whose delivery has already been claimed cannot be withdrawn. Ending the session does
not trigger `onFailedToRenew`.

The Google provider refreshes tokens on the current user's authentication object;
it no longer restores a sign-in as part of refresh. It cancels pending completions
on logout and rejects callbacks for a replaced Google user. Initial Google sign-in
and restoration remain application-owned SDK flows; SDK operations started outside
this provider are outside its lifecycle coordination. Google tests use a controlled
SDK adapter; they do not perform live Google authentication.

## Response validation

Existing `send` calls continue to accept HTTP status codes 200–299 by default.
Use `using` to configure validation for an individual request:

```swift
let operation = Api.using(.get("https://jsonplaceholder.typicode.com/users"))
    .validating(.statusCode([200, 201]))
    .validating(.contentType(["application/json"]))
    .send { (result: Result<[User], Error>) in
        // Validation runs before decoding.
    }
```

`using` creates an immutable builder; the request starts when `send` is called.
It supports `HttpRequest` and `URLRequest`, raw responses, decoded bodies,
decoded responses with HTTP metadata, and async calls. The returned operation
supports cancellation.

Status validation also defaults to 200–299 when using the builder. An explicit
`.statusCode([200, 404])` replaces the current status check; `.statusCode` uses
the default range. Other checks accumulate across `validating` calls and run in
order until one fails. To remove all checks, use `.none`:

```swift
let response: HttpDataResponse = try await Api.using(request)
    .validating(.none)
    .send()
```

Checks added after `.none` start a new validation policy. For example,
`.validating(.none).validating(.contentType(["application/json"]))` checks the
content type while accepting any HTTP status.

Content-type checks ignore case and parameters such as `charset`, accept MIME
wildcards such as `application/*` and `*/*`, and fail when Content-Type is missing.
Custom checks use `.validating(.custom { response in ... })`; throw an error to
reject the response. Custom errors are delivered unchanged. Status failures use
the existing `ApiError.badStatusCode`; content-type failures use
`ResponseValidationError.unacceptableContentType`.

Response interceptors run first. As with existing `send` calls, an interceptor
that handles a response bypasses validation. Transport failures also bypass
validation.

## Why?

Allows for simple middleware/intercepting of request and response. Which is great for custom authentication / request & response manipulation. Also since it just wraps Apple's URLSession API it is very easy to intergrate into existing codebases.

## Advanced Usage

`ProductionEndpoints.swift` Production Target
```swift
private let mobileEndpoints = StaticEndpointInfo(url: "https://...")
```

`StagingEndpoints.swift` Staging Target 
```swift
private let mobileEndpoints = StaticEndpointInfo(url: "https://staging...")
```

`Api.swift`
```swift
class MyApi: Api {
  private var mobileServices: EndpointInfo = mobileEndpoints

  init() {
    let config = DefaultApiConfig(interceptors: [LogInterceptor(level: .verbose)])
    super.init(urlSession: URLSession.shared, config: config)
  }
}

extension MyApi: UserResource {
  @discardableResult
  func getAllUsers(completion: ApiCompletion<[User]>) -> HttpOperation? {
    return send(.get(endpoint: mobileServices, path: "/users"),
                completion: completion)
  }

  @discardableResult
  func createUser(user: CreateUser, completion: ApiCompletion<User>) -> HttpOperation? {
    return send(try! .post(endpoint: mobileServices, path: "/users", body: user),
                completion: completion)
  }
}
```

### EndpointInfo

This saves you from having to repeat your base url and default headers that need to be on all requests like API keys.

```swift
private let mobileEndpoints = StaticEndpointInfo(url: "https://...", headers: ["API-Key": "..."])
```

### Interception

#### Included Inceptors
- `ChaosInterceptor` used to cause chaos. **THIS SHOULD ONLY BE USED WHEN `DEBUG` IS ENABLED AKA `#if DEBUG`**
- `LogInterceptor` used to add logging to all request and response.
- `OAuthInterceptor` used to add OAuth authentication to an API using an `OAuthProvider`.

Creating a custom interceptor allows you modify every request or response, or a specific request and response.

 Example of a inceptor that looks for bad status code and decodes a generic error response body.
```swift
struct MyApiError {
    var code: Int
    var message: String
}

class ErrorInterceptor: ApiInterceptor {
    func api(_ api: Api,
           didReceive result: Result<HttpDataResponse, Error>,
           withId identifier: UUID,
           for request: URLRequest,
           completion: HttpDataCompletion) -> Bool
    {
        if let .success(response) = result { 
            if !response.successful {
                let apiError = api.config.decoder.decode(MyApiError.self, response.data)
                completion(.failure(ApiError.badStatusCode(error: apiError, response: response)))
                return true
            }
        }
        return false
    }
}

let api = Api(config: DefaultApiConfig(interceptors: [ErrorInterceptor()]))
api.send(.get("https://....")) { (result: Result<[User], Error>) in
    switch (result) {
        case let .failure(error):
            if let Api
    }
}
```
