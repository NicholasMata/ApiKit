# ``ApiKit_Google``

Use Google Sign-In credentials with ApiKit's OAuth request coordination.

@Metadata {
  @PageImage(purpose: card, source: "google-card", alt: "ApiKit Google authentication integration")
  @PageImage(purpose: icon, source: "google-icon", alt: "ApiKit Google")
  @PageColor(orange)
}

## Overview

The Google module adapts Google Sign-In to the OAuth provider contract. Configure
Google's SDK and complete initial sign-in or restoration in your application,
then attach ``DefaultGoogleAuthProvider`` to an OAuth interceptor.

The provider refreshes the existing user's authentication object. Token refresh
does not restore a signed-out Google session. Local session ending cancels pending
provider completions and notifies interceptors to discard old-session results.

## Topics

### Essentials

- <doc:UsingGoogleAuthentication>

### Providers and Interceptors

- ``DefaultGoogleAuthProvider``
- ``DefaultGoogleAuthInterceptor``
- ``GoogleAuthError``
