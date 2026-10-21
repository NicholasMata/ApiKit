# Cancelling Requests

Cancel queued requests, pending preparation, or active network tasks.

## Overview

Keep the returned ``HttpOperation`` to cancel an individual request:

```swift
let operation = Api.using(
    HttpRequest.get("https://example.com/report")
).send { (result: Result<HttpDataResponse, Error>) in
    // Cancellation is delivered as ApiError.cancelled.
}

operation.cancel()
```

The fluent API returns an operation directly. Some existing typed `send` and
download overloads return an optional operation; use `operation?.cancel()` with
those signatures.

## Cancellation Boundaries

Cancellation completes the operation once with `ApiError.cancelled`. It works
while the request is queued, waiting for a request modifier, or using a
`URLSessionTask`. If a task exists, the operation cancels it. Repeated or late
callbacks do not resume a cancelled operation.

Cancelling a request does not undo work already performed by a server. It also
does not automatically stop work owned by a custom interceptor or OAuth provider.
For example, other requests can continue sharing an OAuth refresh after one
waiting request is cancelled.

An operation's `id` matches the identifier passed to interceptor hooks and the
identifier in its cancellation error. Use it to correlate those events.

## Cancel Swift Tasks

```swift
let task = Task {
    let response: HttpDataResponse = try await Api.send(
        HttpRequest.get("https://example.com/report")
    )
    return response
}

task.cancel()
```

Cancelling the enclosing Swift task cancels its operation. A task already
cancelled before starting throws `CancellationError` without enqueueing a request.
Cancelling an active request produces `ApiError.cancelled`.

## Queues and Waiting

`requestQueue` starts and limits concurrent operations. Asynchronous preparation
continues through callbacks; waiting for a modifier or shared OAuth refresh does
not occupy a blocked worker thread. An executing operation still counts toward
the queue's concurrency limit until it finishes.

Response processing and final callbacks use `responseQueue`. Keep callbacks
short, and dispatch UI work to the appropriate queue or actor.
