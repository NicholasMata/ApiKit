# Getting Started

Add ApiKit to your application and send your first request.

## Overview

In Xcode, add the package at `https://github.com/NicholasMata/ApiKit` and select
the library products your target needs:

| Product | Import | Purpose |
| --- | --- | --- |
| `ApiKit` | `ApiKit` | Requests, decoding, validation, and cancellation |
| `ApiKit-OAuth` | `ApiKit_OAuth` | Custom providers and OAuth session coordination |
| `ApiKit-Google` | `ApiKit_Google` | Integration with Google Sign-In |

For a package-based application, add the repository to `dependencies` and use
`.product(name: "ApiKit", package: "ApiKit")` in the target's dependencies.
Choose a release containing the APIs you use; unreleased changes on `next` need
an explicit branch dependency until they are released.

## Decode a Response

```swift
import Foundation
import ApiKit

struct User: Decodable {
    let id: Int
    let name: String
}

Api.send(.get("https://example.com/users")) {
    (result: Result<[User], Error>) in

    switch result {
    case .success(let users):
        print(users)
    case .failure(let error):
        print(error)
    }
}
```

With Swift concurrency, the result's type selects body decoding:

```swift
let users: [User] = try await Api.send(
    .get("https://example.com/users")
)
```

The static API uses `Api.default`. Create an ``Api`` instance when you need a
different decoder, interceptor list, response queue, or `URLSession`.

## Configure an API

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase

let config = DefaultApiConfig(
    decoder: decoder,
    interceptors: [LogInterceptor(level: .verbose)]
)
let api = Api(config: config)
```

Final completions run on `config.responseQueue`, which is not necessarily the
main queue. Dispatch UI updates to the main queue or use an appropriate actor.
Choose logging settings appropriate for the request and response data you send.

## Next Steps

- <doc:SendingRequests> describes request bodies, headers, and response types.
- <doc:ValidatingResponses> describes fluent validation.
- <doc:CancellingRequests> describes operations and task cancellation.
- <doc:UsingInterceptors> describes asynchronous request preparation.
