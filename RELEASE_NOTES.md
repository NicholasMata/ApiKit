# Release Notes

## 2.0.0 — Unreleased

The `next` branch includes all 1.1.0 fixes plus the following changes.

### Breaking changes

- `OAuthProvider` requires `endSession()` without a default implementation.
  Custom providers must invalidate outstanding refreshes and clear their own
  credentials, or adopt `SessionOAuthProvider` for coordinated defaults.
- `DefaultGoogleAuthProvider` refreshes the current Google user's tokens instead
  of restoring a previous sign-in. Applications must perform initial Google
  sign-in restoration explicitly.

### Additions

- Fluent, per-request response validation through
  `api.using(request).validating(...).send(...)`. Existing `send` methods retain
  their default status-code validation.
- Protocol-based `SessionOAuthProvider`, coordinated credential storage, and
  `beginSession(with:)` / `endSession()` lifecycle methods that reject stale
  refresh results.
- Session events with multiple subscribers, consumed automatically by
  `OAuthInterceptor` to invalidate pending authentication when sessions change.
- DocC API references and guides for all three modules, a combined documentation
  site, and GitHub Pages deployment tooling.

See [Migrating Providers](ApiKit-OAuth/Sources/ApiKit-OAuth.docc/MigratingProviders.md)
for the OAuth migration steps.

## 1.1.0 — Unreleased

The `1.1.0` branch contains the cancellation and nonblocking execution fixes.
The `next` branch targets 2.0.0 and includes these fixes alongside the new
validation and OAuth session APIs.

### Fixes and additions

- Cancel requests while queued, waiting for interceptors, or sending data.
  Cancellation stops the underlying URLSession task when present and delivers
  completion exactly once with `ApiError.cancelled`.
- Propagate Swift task cancellation to active requests and downloads. A task
  cancelled before starting a request throws `CancellationError`.
- Replace semaphore waits with callback continuations so waiting interceptors
  do not occupy blocked worker threads.
- Share an OAuth refresh among waiting requests. Cancelling a request leaves
  the refresh available to other requests; refresh failure resolves all waiters.
- Expose `HttpOperation.id` to correlate operations, interceptor callbacks,
  and cancellation errors.
- Deliver response interception and final completion on `responseQueue`,
  including responses supplied before a network request is sent.
- Preserve existing request headers while correctly setting `Content-Type` when
  adding an encoded body to a `URLRequest`.
- Replace live-service tests with local fixtures and add CI for code coverage,
  repeated concurrency tests, Thread Sanitizer, release builds, and iOS tests.

### Compatibility

Existing request methods, status-code validation, OAuth provider requirements,
and Google sign-in restoration behavior remain available as in 1.0.16.

`HttpOperation` now reports asynchronous execution. A request occupies a
`requestQueue` concurrency slot until it finishes, including time spent waiting
for interceptors and the network. Dependent operations wait for that finish.
Request preparation continues on internal dispatch queues; response processing
and completion use the configured `responseQueue`.

Cancellation can now deliver a completion where the old implementation left a
caller waiting. Cancelling a request cannot undo work already accepted by the
server. Interceptors' independent asynchronous work, including a shared token
refresh, may continue after an individual request is cancelled.

Fluent validation, required `OAuthProvider.endSession()`, coordinated OAuth
session APIs, and Google refresh behavior changes are reserved for 2.0.0.
