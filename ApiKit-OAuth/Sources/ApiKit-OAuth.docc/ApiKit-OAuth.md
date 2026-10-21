# ``ApiKit_OAuth``

Coordinate authenticated requests, token refresh, and local credential sessions.

@Metadata {
  @PageImage(purpose: card, source: "oauth-card", alt: "ApiKit OAuth credential sessions")
  @PageImage(purpose: icon, source: "oauth-icon", alt: "ApiKit OAuth")
  @PageColor(purple)
}

## Overview

The OAuth module separates credential management from request coordination.
``OAuthProvider`` defines token state, refresh, token attachment, and local session
ending. ``OAuthInterceptor`` asks that provider for credentials and coordinates
requests waiting for refresh.

For a recommended implementation, conform to ``SessionOAuthProvider``. Its
defaults use a stored ``OAuthSessionCoordinator`` to coordinate credential
storage, refresh, and session transitions. The compiler requires your fetching,
token-state, extraction, storage, and clearing hooks.

Fully custom providers can implement ``OAuthProvider`` and
``OAuthSessionEvents`` without adopting the recommended defaults.

## Topics

### Essentials

- <doc:ImplementingProviders>
- <doc:ManagingSessions>
- <doc:MigratingProviders>

### Request Coordination

- ``OAuthInterceptor``
- ``OAuthProvider``
- ``TokenState``
- ``OAuthError``

### Managed Sessions

- ``SessionOAuthProvider``
- ``OAuthSessionCoordinator``
- ``OAuthSessionEvents``
- ``OAuthSessionEvent``
- ``OAuthSubscription``
- ``OAuthSessionEventPublisher``

### Token Storage Integrations

- ``OAuthTokenManagedProvider``
- ``TokenManager``
- ``Token``
- ``OIDCTokenManager``
- ``OIDCTokenResponse``
- ``KeychainHelper``
