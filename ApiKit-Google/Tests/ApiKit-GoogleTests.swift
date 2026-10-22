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
    let signIn = StubSignIn()
    let provider = DefaultGoogleAuthProvider(client: signIn)
    XCTAssertEqual(provider.tokenState, .missing)
    XCTAssertEqual(signIn.restoreCount, 0)
  }

  func testRefreshRestoresPreviousSignInAndReturnsToken() {
    let signIn = StubSignIn()
    signIn.restoredUser = StubGoogleUser()
    let provider = DefaultGoogleAuthProvider(client: signIn)
    var calls = 0
    provider.refreshToken { result in
      XCTAssertEqual(try? result.get(), "fixture-access-token")
      calls += 1
    }
    XCTAssertEqual(signIn.restoreCount, 1)
    XCTAssertEqual(calls, 1)
  }

  func testRefreshForwardsRestorationError() {
    let signIn = StubSignIn()
    signIn.restorationError = URLError(.timedOut)
    let provider = DefaultGoogleAuthProvider(client: signIn)
    var calls = 0
    provider.refreshToken { result in
      guard case let .failure(error) = result else { return XCTFail("Expected timeout") }
      XCTAssertEqual((error as? URLError)?.code, .timedOut)
      calls += 1
    }
    XCTAssertEqual(calls, 1)
  }

  func testRestorationWithoutUserReportsUnknownError() {
    let provider = DefaultGoogleAuthProvider(client: StubSignIn())
    var calls = 0
    provider.refreshToken { result in
      if case .failure(GoogleAuthError.unknown) = result {} else { XCTFail("Expected unknown error") }
      calls += 1
    }
    XCTAssertEqual(calls, 1)
  }

  func testMissingTokenReportsNoToken() {
    let signIn = StubSignIn()
    signIn.restoredUser = StubGoogleUser()
    let provider = MissingTokenProvider(client: signIn)
    XCTAssertEqual(provider.tokenState, .expired)
    var calls = 0
    provider.refreshToken { result in
      if case .failure(OAuthError.noToken) = result {} else { XCTFail("Expected missing token") }
      calls += 1
    }
    XCTAssertEqual(calls, 1)
  }

  func testCurrentUserTokenStateReflectsExpiration() {
    let signIn = StubSignIn()
    let user = StubGoogleUser()
    signIn.restoredUser = user
    let provider = DefaultGoogleAuthProvider(client: signIn)
    XCTAssertEqual(provider.tokenState, .valid(token: "fixture-access-token"))
    user.credentials.expiration = Date.distantPast
    XCTAssertEqual(provider.tokenState, .expired)
  }
}

private final class MissingTokenProvider: DefaultGoogleAuthProvider {
  override func token(for _: GIDGoogleUser) -> String? { nil }
}

private final class StubSignIn: GoogleSignInClient {
  var restoredUser: GIDGoogleUser?
  var restorationError: Error?
  private(set) var restoreCount = 0
  var currentUser: GIDGoogleUser? { restoredUser }
  func restorePreviousSignIn(callback: GIDSignInCallback? = nil) {
    restoreCount += 1
    callback?(restoredUser, restorationError)
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
