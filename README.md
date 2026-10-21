# ApiKit

[![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)](#installation)

A simple way to connect your swift code to your APIs.

This branch targets **1.1.0**. See the [release notes](RELEASE_NOTES.md) for
cancellation fixes and execution changes. Development for **2.0.0** continues
on [`next`](https://github.com/NicholasMata/ApiKit/tree/next).

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
