# ``ApiKit``

Send HTTP requests, decode responses, and coordinate validation and cancellation.

@Metadata {
  @PageImage(purpose: card, source: "apikit-card", alt: "ApiKit HTTP requests and responses")
  @PageImage(purpose: icon, source: "apikit-icon", alt: "ApiKit")
  @PageColor(blue)
}

## Overview

ApiKit wraps Foundation's `URLSession` with request builders, callback and async
APIs, cancellable operations, and request and response interceptors. Use the core
module on its own, or add `ApiKit_OAuth` and `ApiKit_Google` for authentication.

The package supports iOS 12 and macOS 12 or later. Async request APIs require iOS
13 or later. The callback APIs remain available on iOS 12.

```swift
import ApiKit

struct User: Decodable {
    let id: Int
    let name: String
}

let users: [User] = try await Api.send(
    .get("https://example.com/users")
)
```

Requests accept status codes 200–299 by default. Use ``ApiCall`` to configure
per-request validation while keeping existing `send` calls unchanged.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:SendingRequests>
- <doc:ValidatingResponses>
- <doc:CancellingRequests>
- <doc:UsingInterceptors>

### Requests and Responses

- ``Api``
- ``ApiCall``
- ``HttpRequest``
- ``HttpMethod``
- ``HttpOperation``
- ``HttpDataResponse``
- ``HttpResponse``

### Configuration

- ``ApiConfig``
- ``DefaultApiConfig``
- ``EndpointInfo``
- ``StaticEndpointInfo``

### Validation and Errors

- ``ResponseValidation``
- ``ResponseValidationError``
- ``ApiError``

### Interception

- ``ApiInterceptor``
- ``LogInterceptor``
- ``ConnectivityInterceptor``
- ``ChaosInterceptor``

### Serialization

- ``DataEncoder``
- ``DataDecoder``
- ``URLEncodedFormEncoder``
