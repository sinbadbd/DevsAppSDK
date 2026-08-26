# Changelog

## 2.0.0

The API now requires `Authorization: Bearer <token>` and rejects
unauthenticated requests with 401.

**Breaking**

- New `DevsAppError.unauthorized(statusCode:message:)` case. Exhaustive
  `switch`es over `DevsAppError` must add a case for it — the compiler will
  point at each one.

**Added**

- `DevsAppConfiguration.token` and `.tokenProvider` for a token that can change
  or expire. The provider is asked once per call, not once per retry.
- `DevsAppClient.setToken(_:)` to swap the token at runtime; it clears cached
  responses so data fetched as one identity is never served to another.
- `DevsAppClient.isAuthenticated` and `DevsAppError.requiresAuthentication`.
- 401 and 403 map to `.unauthorized` and are never retried, so a 401 on a slug
  lookup is no longer reported as a missing app.

## 1.0.0

Initial release: `listApps()`, `app(slug:)`, models, sealed error type,
in-memory TTL cache, retries, request coalescing, and optional SwiftUI screens.
