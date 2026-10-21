# Implementing Providers

Keep application-specific fetching and storage while using the recommended coordination defaults.

## Overview

Conform your class to ``SessionOAuthProvider``. Retain one coordinator for that
provider's lifetime and implement five credential hooks. Do not create a new
coordinator in a computed property; pending refreshes and subscriptions must
share the same state.

The example below uses application-defined persistence through `CredentialStore`.
Its reads and writes must be thread-safe and its writes must finish synchronously.

```swift
import Foundation
import ApiKit
import ApiKit_OAuth

struct Credentials: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

protocol CredentialStore: AnyObject {
    var tokenState: TokenState { get }
    var refreshToken: String? { get }
    func save(_ credentials: Credentials)
    func clear()
}

final class ExampleOAuthProvider: SessionOAuthProvider {
    let session = OAuthSessionCoordinator<Credentials>()

    private let tokenURL: URL
    private let store: CredentialStore
    private let tokenApi: Api

    init(tokenURL: URL, store: CredentialStore, tokenApi: Api) {
        self.tokenURL = tokenURL
        self.store = store
        self.tokenApi = tokenApi
    }

    func readTokenState() -> TokenState {
        store.tokenState
    }

    func fetchCredentials(
        completion: @escaping (Result<Credentials, Error>) -> Void
    ) {
        guard let token = store.refreshToken else {
            completion(.failure(OAuthError.noToken))
            return
        }

        do {
            let request = try HttpRequest.post(
                tokenURL,
                body: ["grant_type": "refresh_token", "refresh_token": token],
                encoder: URLEncodedFormEncoder(),
                contentType: "application/x-www-form-urlencoded"
            )
            tokenApi.send(request, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func accessToken(from credentials: Credentials) -> String {
        credentials.accessToken
    }

    func storeCredentials(_ credentials: Credentials) {
        store.save(credentials)
    }

    func clearCredentials() {
        store.clear()
    }
}
```

`tokenApi` can be an existing open API. It must not use the OAuth interceptor
whose refresh it is performing; that would make the refresh wait on itself.
Configure any client authentication and headers required by your token endpoint.

## Implement Token State

Return `.valid(token:)` for an access token that is usable, `.expired` when a
refresh can obtain a new token, and `.missing` when no usable credentials remain.
The application owns expiration policy and persisted credential restoration.

The coordinator reads this state before requests need credentials. Existing
persisted credentials work on application startup without calling `beginSession`.
Ensure the store has loaded them before sending authenticated requests.

## Storage Contract

`fetchCredentials` returns the full response without storing it. The defaults
check the session before calling `storeCredentials` and completing refresh with
the extracted access token. Ending a session and storing a refresh response use
the same lock, so a late response cannot restore an ended session.

The token-state, token-extraction, storage, and clearing hooks run under that
lock. Keep them short and synchronous. Do not call lifecycle methods from them
or synchronously dispatch to a queue that may be waiting for the provider.
Network fetching, events, and result callbacks run outside the credential lock.

For refresh-token rotation, store a replacement refresh token when the server
returns one. If a refresh response omits that field, preserve the current token
as appropriate for your server. `beginSession(with:)` clears previous credentials
before storing a new login, preventing accidental reuse of the old account's data.

## Customize or Replace Defaults

Implement `attach(token:to:)` to customize the default Authorization bearer header.
The protocol defaults can also be replaced, but doing so makes their lifecycle
and synchronization guarantees your implementation's responsibility.

``OAuthTokenManagedProvider`` is a separate existing integration for token managers;
it does not itself provide the managed session coordination described here.
