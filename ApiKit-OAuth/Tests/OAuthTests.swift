import ApiKit
@testable import ApiKit_OAuth
import XCTest

final class ApiKitOAuthTests: XCTestCase {
  func testTokenStateUsesAccessTokenBeforeRefreshToken() {
    let manager = MemoryTokenManager()
    let provider = ManagedProvider(manager: manager)
    XCTAssertEqual(provider.tokenState, .missing)
    manager.refreshToken = token("refresh", expiresIn: 3600)
    XCTAssertEqual(provider.tokenState, .expired)
    manager.accessToken = token("access", expiresIn: 3600)
    XCTAssertEqual(provider.tokenState, .valid(token: "access"))
    manager.accessToken = token("old", expiresIn: -1)
    XCTAssertEqual(provider.tokenState, .expired)
    manager.refreshToken = token("old refresh", expiresIn: -1)
    XCTAssertEqual(provider.tokenState, .missing)
    manager.accessToken = token("access", expiresIn: 3600)
    XCTAssertEqual(provider.tokenState, .valid(token: "access"))
  }

  func testExpirationPaddingAvoidsNearlyExpiredTokens() {
    XCTAssertTrue(token("fresh", expiresIn: 3600).isValid())
    XCTAssertTrue(token("near expiration", expiresIn: 30).isExpired())
    XCTAssertTrue(token("expired", expiresIn: -1).isExpired())
  }

  func testDefaultAttachmentPreservesOtherHeadersAndOriginalRequest() {
    let provider = ManagedProvider(manager: MemoryTokenManager())
    var request = URLRequest(url: URL(string: "https://apikit.test")!)
    request.setValue("original", forHTTPHeaderField: "Authorization")
    request.setValue("trace", forHTTPHeaderField: "X-Trace")
    let attached = provider.attach(token: "access", to: request)
    XCTAssertEqual(attached.value(forHTTPHeaderField: "Authorization"), "Bearer access")
    XCTAssertEqual(attached.value(forHTTPHeaderField: "X-Trace"), "trace")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "original")
  }

  private func token(_ value: String, expiresIn: Int) -> Token {
    Token(token: value, expiresIn: expiresIn, retrievedOn: Date())
  }
}

private final class ManagedProvider: OAuthTokenManagedProvider {
  func signOut() { tokenManager.clear() }
  var tokenManager: TokenManager
  init(manager: TokenManager) { tokenManager = manager }
  func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
    completion(.success("refreshed"))
  }
}

private final class MemoryTokenManager: TokenManager {
  var accessToken: Token?
  var refreshToken: Token?
  func decode(from _: Data) {}
  func clear() {
    accessToken = nil
    refreshToken = nil
  }
}
