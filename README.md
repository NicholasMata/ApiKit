# ApiKit

[![Platforms](https://img.shields.io/badge/Platforms-iOS_12%2B_%7C_macOS_12%2B-blue)](#installation)
[![Tests](https://github.com/NicholasMata/ApiKit/actions/workflows/tests.yml/badge.svg?branch=next)](https://github.com/NicholasMata/ApiKit/actions/workflows/tests.yml?query=branch%3Anext)
[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](docs/README.md)
[![Deploy DocC](https://github.com/NicholasMata/ApiKit/actions/workflows/deploy-docc.yml/badge.svg)](https://github.com/NicholasMata/ApiKit/actions/workflows/deploy-docc.yml)

A Swift networking library built on URLSession, with response decoding,
per-request validation, cancellable operations, and extensible interceptors.
Optional modules provide OAuth session coordination and Google Sign-In integration.

This branch targets **2.0.0** and builds on
[`1.1.0`](https://github.com/NicholasMata/ApiKit/tree/1.1.0), which contains the
cancellation and nonblocking execution fixes. See the
[release notes](RELEASE_NOTES.md) for each release's scope and
[Testing](docs/TESTING.md) for local checks, CI jobs, and coverage reports.

## Installation

Add [ApiKit](https://github.com/NicholasMata/ApiKit) through Xcode's package
dependencies, then select the library products your target needs. Choose a release,
or the `next` branch for unreleased changes.

The package declares iOS 12 and macOS 12 minimums. Async request APIs require
iOS 13 or later; callback APIs remain available on iOS 12.

## Quick Start

```swift
import Foundation
import ApiKit

struct User: Decodable {
    let id: Int
    let name: String
}

let users: [User] = try await Api.send(
    .get("https://example.com/users")
)
```

### Send JSON

Pass an `Encodable` body and decode the response into your own model:

```swift
struct NewUser: Encodable {
    let name: String
}

let request = try HttpRequest.post(
    "https://example.com/users",
    body: NewUser(name: "Taylor")
)
let created: User = try await Api.send(request)
```

### Validate a Response

Configure checks for one request using a fluent builder:

```swift
let users: [User] = try await Api.using(
    HttpRequest.get("https://example.com/users")
)
.validating(.statusCode([200, 201]))
.validating(.contentType(["application/json"]))
.send()
```

Requests accept 200–299 by default. Use `.validating(.none)` to clear the checks.
See [response validation](ApiKit/Sources/ApiKit.docc/ValidatingResponses.md) for custom policies.

### Use Callbacks and Cancel Requests

Callback APIs work on iOS 12. Keep the returned operation when you need cancellation:

```swift
let operation = Api.send(.get("https://example.com/users")) {
    (result: Result<[User], Error>) in

    switch result {
    case .success(let users):
        print(users)
    case .failure(let error):
        print(error)
    }
}

// When the request is no longer needed:
operation?.cancel()
```

Swift task cancellation also cancels its request. See
[cancellation](ApiKit/Sources/ApiKit.docc/CancellingRequests.md) for lifecycle details.

### Configure an API

Choose a decoder and interceptors, and retain HTTP metadata alongside a decoded body:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase

let api = Api(config: DefaultApiConfig(
    decoder: decoder,
    interceptors: [LogInterceptor(level: .verbose)]
))

let response: HttpResponse<[User]> = try await api.send(
    .get("https://example.com/users")
)
print(response.statusCode, response.body)
```

Implement `ApiInterceptor` to customize headers, prepare requests asynchronously,
or handle responses. See [interceptors](ApiKit/Sources/ApiKit.docc/UsingInterceptors.md).

### Coordinate OAuth Sessions

Given your application's `SessionOAuthProvider` instance and a successful login
response, use the same provider for authenticated requests and session changes:

```swift
import ApiKit_OAuth

let authenticatedApi = Api(config: DefaultApiConfig(
    interceptors: [OAuthInterceptor(provider: provider)]
))

provider.beginSession(with: credentials) // After a successful login.
provider.endSession()                   // When ending the local session.
```

The provider defaults coordinate refresh, credential storage, and waiting requests.
See [implementing providers](ApiKit-OAuth/Sources/ApiKit-OAuth.docc/ImplementingProviders.md)
for the required hooks and [session management](ApiKit-OAuth/Sources/ApiKit-OAuth.docc/ManagingSessions.md)
for lifecycle behavior.

## Modules

| Product | Import | Documentation |
| --- | --- | --- |
| `ApiKit` | `ApiKit` | [Requests, validation, cancellation, and interceptors](ApiKit/Sources/ApiKit.docc/ApiKit.md) |
| `ApiKit-OAuth` | `ApiKit_OAuth` | [Providers, credential sessions, and refresh coordination](ApiKit-OAuth/Sources/ApiKit-OAuth.docc/ApiKit-OAuth.md) |
| `ApiKit-Google` | `ApiKit_Google` | [Google Sign-In integration](ApiKit-Google/Sources/ApiKit-Google.docc/ApiKit-Google.md) |

## Documentation

Detailed usage and API references live in the DocC catalogs linked above.
Existing OAuth integrations can follow the
[provider migration guide](ApiKit-OAuth/Sources/ApiKit-OAuth.docc/MigratingProviders.md).

The [documentation tooling guide](docs/README.md) covers building the combined
site, previewing it locally, and publishing it through GitHub Pages.
