# Validating Responses

Configure checks for one request using an immutable fluent builder.

## Overview

Both existing `send` calls and `using` builders accept HTTP status codes 200–299
by default. Creating an ``ApiCall`` does not enqueue a request; `send` starts it.

```swift
let response: HttpDataResponse = try await Api.using(
    HttpRequest.get("https://example.com/users")
)
.validating(.statusCode([200, 201]))
.validating(.contentType(["application/json"]))
.send()
```

An explicit status check replaces the existing status check. Additional checks
accumulate and run in order until one fails. The `.statusCode` shorthand selects
200–299 again.

## Disable or Replace Checks

```swift
let response: HttpDataResponse = try await Api.using(request)
    .validating(.none)
    .send()
```

`.none` clears all checks already configured on that builder. Checks added after
it start a new policy. For example, `.validating(.none).validating(.contentType(
["application/json"]))` checks the media type while accepting any HTTP status.
An empty status-code list rejects every status.

## Check Content Types

Content-type checks ignore case and parameters such as `charset`. They support
exact media types, `application/*`, and `*/*`. A missing Content-Type fails even
when a wildcard is accepted. An empty accepted list also fails.

## Supply a Custom Check

```swift
enum EmptyResponse: Error {
    case missingBody
}

let response: HttpDataResponse = try await Api.using(request)
    .validating(.custom { response in
        guard !response.data.isEmpty else {
            throw EmptyResponse.missingBody
        }
    })
    .send()
```

Throw to reject a response. Custom errors are delivered unchanged. Status
failures retain `ApiError.badStatusCode`; media-type failures use
``ResponseValidationError``.

## Understand Interceptor Ordering

Response interceptors run first. If an interceptor handles a response by returning
`true`, its completion bypasses validation. Otherwise validators run on the
response queue before decoding. Transport errors bypass response validators.
This preserves the behavior of existing sends and custom response interceptors.
