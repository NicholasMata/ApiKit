# Using Interceptors

Customize request preparation and response handling with explicit callback ownership.

## Overview

Implement ``ApiInterceptor`` on a class and configure an API with its instances:

```swift
import Foundation
import ApiKit

final class HeaderInterceptor: ApiInterceptor {
    func api(
        _ api: Api,
        modifyRequest request: URLRequest,
        withId identifier: UUID,
        onNewRequest: @escaping (URLRequest?) -> Void
    ) {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        onNewRequest(request)
    }
}

let api = Api(config: DefaultApiConfig(interceptors: [HeaderInterceptor()]))
```

The class-constrained default implementations let you implement only the hooks
you need. Import Foundation alongside ApiKit for Foundation types in your source.

## Request Preparation

`modifyRequest` hooks run in configuration order. Call `onNewRequest` once with
the modified or original request. Passing `nil` cancels the operation. You may
return before calling the callback and resume it asynchronously; do not block a
thread waiting for that work. Until the callback arrives, preparation is pending.

Cancelling the operation prevents a late callback from sending its request.
Interceptors still own any independent work they start.

## Early and Received Responses

`willSendRequest` can provide an early result instead of sending to the network.
Return `true` when you take ownership of its completion, and call that completion
once when the result is ready. Return `false` to continue normal execution.

`didReceive` runs on the API's response queue. Return `true` and complete with
your handled result to replace normal processing. Return `false` to leave the
result to subsequent interceptors and validation. Handled responses bypass
validation, matching existing ApiKit behavior.

Request hooks do not have main-thread affinity. Protect shared interceptor state
when the same interceptor serves concurrent requests or multiple API instances.

## Built-in Interceptors

- ``LogInterceptor`` records request and response information.
- ``ConnectivityInterceptor`` checks connectivity before proceeding.
- ``ChaosInterceptor`` can deliberately disrupt requests for testing.

The OAuth module supplies a coordinator for requests waiting on token refresh.
Its provider contract and session lifecycle are documented under `ApiKit_OAuth`.
