# Sending Requests

Build requests and choose raw responses, decoded bodies, or decoded HTTP responses.

## Overview

``HttpRequest`` provides HTTP method helpers. You can also pass a Foundation
`URLRequest` directly, including its headers and timeout settings.

```swift
let request = HttpRequest.get("https://example.com/users")
let response: HttpDataResponse = try await Api.send(request)
print(response.statusCode)
print(response.data)
```

## Send JSON or Form Data

```swift
struct NewUser: Encodable {
    let name: String
}

let request = try HttpRequest.post(
    "https://example.com/users",
    body: NewUser(name: "Taylor")
)
```

For a form body, select both the encoder and the content type:

```swift
let request = try HttpRequest.post(
    "https://example.com/form",
    body: ["name": "Taylor"],
    encoder: URLEncodedFormEncoder(),
    contentType: "application/x-www-form-urlencoded"
)
```

Use ``EndpointInfo`` to share a base URL and default headers between resources:

```swift
let endpoint = StaticEndpointInfo(
    url: "https://example.com",
    headers: ["Accept": "application/json"]
)
let request = HttpRequest.get(endpoint: endpoint, path: "/users")
```

## Choose a Response Type

```swift
struct User: Decodable {
    let id: Int
    let name: String
}

let request = HttpRequest.get("https://example.com/users")

let body: [User] = try await Api.send(request)
let decoded: HttpResponse<[User]> = try await Api.send(request)
let raw: HttpDataResponse = try await Api.send(request)
```

`HttpResponse` retains HTTP information alongside `body`. `HttpDataResponse`
exposes the raw bytes without body decoding. Each `send` above starts its own
request; choose the form your call needs.

Decoded calls use the configured ``DataDecoder`` unless you supply one. A
decoding failure produces `ApiError.serializationFailed` with the underlying
error and the raw response. HTTP status validation happens before decoding.

## Save a Response to a File

```swift
let file = try await Api.default.download(
    HttpRequest.get("https://example.com/report"),
    asFileName: "report.pdf"
)
```

The current download helper obtains the response body as data before writing it
to disk. It uses the same validation and cancellation behavior as ordinary sends.
