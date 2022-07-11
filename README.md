# ApiKit

[![Platform](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-4E4E4E.svg?colorA=28a745)](#installation)

A simple way to connect your swift code to your APIs.

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

 Add Azure subscription key to all requests
```swift

```


