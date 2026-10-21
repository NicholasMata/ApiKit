@testable import ApiKit_Google
import ApiKit_OAuth
import GoogleSignIn
import XCTest

final class ApiKitGoogleTests: XCTestCase {
  func testPublicInitializerKeepsSharedSDKInstance() {
    let provider = DefaultGoogleAuthProvider()
    XCTAssertTrue(provider.googleSignIn === GIDSignIn.sharedInstance)
  }

  func testMissingCurrentUserHasMissingTokenState() {
    let client = TestGoogleClient()
    let provider = DefaultGoogleAuthProvider(client: client)
    XCTAssertEqual(provider.tokenState, .missing)
    XCTAssertTrue(client.refreshedUsers.isEmpty)
  }

  func testCurrentUserTokenStateReflectsExpiration() {
    let client = TestGoogleClient()
    let user = StubGoogleUser()
    client.currentUser = user
    let provider = DefaultGoogleAuthProvider(client: client)
    XCTAssertEqual(provider.tokenState, .valid(token: "fixture-access-token"))
    user.credentials.expiration = Date.distantPast
    XCTAssertEqual(provider.tokenState, .expired)
  }

  func testCurrentUserWithoutTokenHasExpiredTokenState() {
    let client = TestGoogleClient()
    client.currentUser = StubGoogleUser()
    let provider = TestGoogleProvider(client: client)
    provider.providedToken = nil
    XCTAssertEqual(provider.tokenState, .expired)
  }

  func testSessionChangeDuringTokenStateReadRejectsToken() {
    let client = TestGoogleClient()
    client.currentUser = StubGoogleUser()
    let provider = TestGoogleProvider(client: client)
    provider.onToken = { [weak provider] in provider?.signOut() }
    XCTAssertEqual(provider.tokenState, .missing)
    XCTAssertNil(client.currentUser)
  }

  func testRefreshUsesExistingUserAndCompletesOnce() {
    let client = TestGoogleClient()
    let user = GIDGoogleUser()
    client.currentUser = user
    let provider = TestGoogleProvider(client: client)
    var count = 0
    provider.refreshToken { result in
      XCTAssertEqual(try? result.get(), "fresh-token")
      count += 1
    }
    XCTAssertTrue(client.refreshedUsers.first === user)
    client.finish(0)
    client.finish(0)
    XCTAssertEqual(count, 1)
  }

  func testSignOutCancelsRefreshAndLateCallbackCannotRestoreSession() {
    let client = TestGoogleClient()
    client.currentUser = GIDGoogleUser()
    let provider = TestGoogleProvider(client: client)
    var completions = 0
    var events = 0
    let subscription = provider.subscribe(.signOut) { events += 1 }
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else { return XCTFail("Expected ended session") }
      completions += 1
    }
    provider.signOut()
    XCTAssertNil(client.currentUser)
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(events, 1)
    client.finish(0)
    XCTAssertNil(client.currentUser)
    XCTAssertEqual(client.signOutCount, 1)
    XCTAssertEqual(completions, 1)
    withExtendedLifetime(subscription) {}
  }

  func testOldRefreshDoesNotAffectNewGoogleUser() {
    let client = TestGoogleClient()
    client.currentUser = GIDGoogleUser()
    let provider = TestGoogleProvider(client: client)
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else { return XCTFail("Expected ended session") }
    }
    provider.signOut()
    let newUser = GIDGoogleUser()
    client.currentUser = newUser
    var token: String?
    provider.refreshToken { token = try? $0.get() }
    client.finish(0)
    XCTAssertNil(token)
    XCTAssertTrue(client.currentUser === newUser)
    client.finish(1)
    XCTAssertEqual(token, "fresh-token")
    XCTAssertTrue(client.currentUser === newUser)
    XCTAssertEqual(client.signOutCount, 1)
  }

  func testAccountChangeRejectsOldRefreshEvenWithoutProviderSignOut() {
    let client = TestGoogleClient()
    client.currentUser = GIDGoogleUser()
    let provider = TestGoogleProvider(client: client)
    var count = 0
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else { return XCTFail("Expected ended session") }
      count += 1
    }
    client.currentUser = GIDGoogleUser()
    client.finish(0)
    XCTAssertEqual(count, 1)
  }

  func testMissingUserDoesNotAttemptRestoration() {
    let client = TestGoogleClient()
    let provider = TestGoogleProvider(client: client)
    provider.refreshToken { result in
      guard case .failure(OAuthError.noToken) = result else { return XCTFail("Expected missing token") }
    }
    XCTAssertTrue(client.refreshedUsers.isEmpty)
  }

  func testRefreshErrorIsForwardedUnchanged() {
    let client = TestGoogleClient()
    client.currentUser = GIDGoogleUser()
    let provider = TestGoogleProvider(client: client)
    provider.refreshToken { result in
      guard case let .failure(error) = result else { return XCTFail("Expected timeout") }
      XCTAssertEqual((error as? URLError)?.code, .timedOut)
    }
    client.finish(0, error: URLError(.timedOut))
  }

  func testMissingAccessTokenReportsNoToken() {
    let client = TestGoogleClient()
    client.currentUser = GIDGoogleUser()
    let provider = TestGoogleProvider(client: client)
    provider.providedToken = nil
    provider.refreshToken { result in
      guard case .failure(OAuthError.noToken) = result else { return XCTFail("Expected missing token") }
    }
    client.finish(0)
  }

  func testSignOutDuringTokenExtractionRejectsResult() {
    let client = TestGoogleClient()
    client.currentUser = GIDGoogleUser()
    let provider = TestGoogleProvider(client: client)
    provider.onToken = { [weak provider] in provider?.signOut() }
    var count = 0
    provider.refreshToken { result in
      guard case .failure(OAuthError.sessionEnded) = result else { return XCTFail("Expected ended session") }
      count += 1
    }
    client.finish(0)
    XCTAssertEqual(count, 1)
    XCTAssertNil(client.currentUser)
  }
}

private final class TestGoogleProvider: DefaultGoogleAuthProvider {
  var providedToken: String? = "fresh-token"
  var onToken: (() -> Void)?
  override func token(for _: GIDGoogleUser) -> String? {
    onToken?()
    return providedToken
  }
}

private final class TestGoogleClient: GoogleOAuthClient {
  var currentUser: GIDGoogleUser?
  var refreshedUsers: [GIDGoogleUser] = []
  private var callbacks: [(Error?) -> Void] = []
  private(set) var signOutCount = 0

  func refreshTokens(for user: GIDGoogleUser, completion: @escaping (Error?) -> Void) {
    refreshedUsers.append(user)
    callbacks.append(completion)
  }

  func finish(_ index: Int, error: Error? = nil) {
    callbacks[index](error)
  }

  func signOut() {
    currentUser = nil
    signOutCount += 1
  }
}

private final class StubGoogleUser: GIDGoogleUser {
  let credentials = StubAuthentication()
  override var authentication: GIDAuthentication { credentials }
}

private final class StubAuthentication: GIDAuthentication {
  var expiration = Date.distantFuture
  override var accessToken: String { "fixture-access-token" }
  override var accessTokenExpirationDate: Date { expiration }
}
