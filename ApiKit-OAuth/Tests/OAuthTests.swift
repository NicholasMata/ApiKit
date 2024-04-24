//
//  ApiKit-OAuthTests.swift
//
//
//  Created by Nicholas Mata on 4/15/24.
//

import ApiKit
@testable import ApiKit_OAuth
import XCTest

public struct DummyLoginInfo: Codable {
  public let username: String
  public let password: String
  public let expiresInMins: Int
}

public struct DummyLoginResponse: Codable {
  public var token: String
}

public struct DummyProduct: Codable {
  public var id: Int
  public var title: String
}

public class DummyProvider: OAuthTokenManagedProvider {
  public var tokenManager: any TokenManager = OIDCTokenManager(account: "tests")

  public func refreshToken(completion: @escaping (Result<String, Error>) -> Void) {
    do {
      Thread.sleep(forTimeInterval: 1)
      let loginBody = DummyLoginInfo(username: "kminchelle", password: "0lelplR", expiresInMins: 60)
      try Api.send(.post("https://dummyjson.com/auth/login", body: loginBody)) { (result: Result<DummyLoginResponse, Error>) in
        switch result {
        case let .success(response):
          self.tokenManager.accessToken = Token(token: response.token, expiresIn: loginBody.expiresInMins * 60, retrievedOn: Date())
          completion(.success(response.token))
        case let .failure(err):
          completion(.failure(err))
        }
      }
    } catch {
      completion(.failure(error))
    }
  }
}

final class ApiKitOAuthTests: XCTestCase {
  func testOAuthTokenManagedProvider() throws {
    // This to pretend we have a valid refresh token
    let provider = DummyProvider()
    provider.tokenManager.refreshToken = Token(token: "fakeRefresh", expiresIn: 4600, retrievedOn: Date())

    let interceptors: [ApiInterceptor] = [ConnectivityInterceptor(), OAuthInterceptor(provider: provider)]
    let config = DefaultApiConfig(interceptors: interceptors)
    let api = Api(config: config)
    let p1Expectation = self.expectation(description: "Product1")

    var product: DummyProduct? = nil

    api.send(.get("https://dummyjson.com/auth/products/1")) { (result: Result<DummyProduct, Error>) in
      switch result {
      case let .success(response):
        product = response
        p1Expectation.fulfill()
      case .failure:
        XCTAssert(false)
      }
    }

    let p2Expectation = self.expectation(description: "Product2")
    var product2: DummyProduct? = nil
    api.send(.get("https://dummyjson.com/auth/products/2")) { (result: Result<DummyProduct, Error>) in
      switch result {
      case let .success(response):
        product2 = response
        p2Expectation.fulfill()
      case .failure:
        XCTAssert(false)
      }
    }

    waitForExpectations(timeout: 1.5) { _ in
      XCTAssertNotNil(product)
      XCTAssertEqual(product!.id, 1)

      XCTAssertNotNil(product2)
      XCTAssertEqual(product2!.id, 2)
    }
  }
}
