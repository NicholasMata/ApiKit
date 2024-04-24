//
//  ApiIntegrationTests.swift
//
//
//  Created by Nicholas Mata on 6/9/22.
//

@testable import ApiKit
import XCTest

struct CreateUser: Encodable {
  public var name: String
}

struct User: Decodable {
  public var id: Int
  public var name: String
}

protocol UserResource {
  @discardableResult
  func getAllUsers(completion: ApiCompletion<[User]>) -> HttpOperation?
  @discardableResult
  func createUser(user: CreateUser, completion: ApiCompletion<User>) -> HttpOperation?
}

class JsonPlaceholderApi: Api {
  var mobileServices: EndpointInfo

  init(mobileServices: EndpointInfo) {
    self.mobileServices = mobileServices
    let config = DefaultApiConfig(interceptors: [LogInterceptor(level: .verbose)])
    super.init(urlSession: URLSession.shared, config: config)
  }
}

extension JsonPlaceholderApi: UserResource {
  @discardableResult
  func getAllUsers(completion: ApiCompletion<[User]>) -> HttpOperation? {
    return send(.get(endpoint: mobileServices, path: "/users"),
                completion: completion)
  }

  @discardableResult
  func createUser(user: CreateUser, completion: ApiCompletion<User>) -> HttpOperation? {
    return send(try! .post(endpoint: mobileServices, path: "/users", body: user),
                completion: completion)
  }
}

final class ApiTests: XCTestCase {
  let api = JsonPlaceholderApi(mobileServices:
    StaticEndpointInfo(url: "https://jsonplaceholder.typicode.com"))

  func testGetRequest() throws {
    let expectation = self.expectation(description: "Users")
    var expectedUsers: [User]?

    api.getAllUsers { result in
      switch result {
      case let .success(users):
        expectedUsers = users
        expectation.fulfill()
      case .failure:
        break
      }
    }

    waitForExpectations(timeout: 10) { _ in
      XCTAssertNotNil(expectedUsers)
    }
  }

  func testMultipleRequests() throws {
    let expectation = self.expectation(description: "Users")
    var expectedUsers: [User]?

    api.getAllUsers { result in
      switch result {
      case let .success(users):
        expectedUsers = users
        expectation.fulfill()
      case .failure:
        break
      }
    }
    
    let nextExpectation = self.expectation(description: "NextUsers")
    var nextExpectedUsers: [User]?

    api.getAllUsers { result in
      switch result {
      case let .success(users):
        nextExpectedUsers = users
        nextExpectation.fulfill()
      case .failure:
        break
      }
    }

    waitForExpectations(timeout: 10) { _ in
      XCTAssertNotNil(expectedUsers)
      XCTAssertNotNil(nextExpectedUsers)
    }
  }

  func testPostRequest() throws {
    let expectation = self.expectation(description: "Users")
    var expectedUser: User?

    api.createUser(user: CreateUser(name: "Test")) { result in
      switch result {
      case let .success(user):
        expectedUser = user
        expectation.fulfill()
      case .failure:
        break
      }
    }

    waitForExpectations(timeout: 10) { _ in
      XCTAssertNotNil(expectedUser)
      XCTAssertEqual(expectedUser!.id, 11)
      XCTAssertEqual(expectedUser!.name, "Test")
    }
  }

  func testDownload() throws {
    var expectation = expectation(description: "Download File")
    var filePath: URL?
    let api = Api(config: DefaultApiConfig(interceptors: [ConnectivityInterceptor(), LogInterceptor(level: .verbose)]))
    let request = HttpRequest.get("http://research.nhm.org/pdfs/10840/10840.pdf")

    let task = api.download(request, asFileName: "dummy.pdf", completion: { result in
      if case let .success(url) = result {
        filePath = url
        expectation.fulfill()
      }
    })

    var observation: NSKeyValueObservation?
    task?.onUrlSessionTask = { urlSessionTask in
      observation = urlSessionTask.progress.observe(\.fractionCompleted) { progress, _ in
        if !progress.isIndeterminate {
          print(progress.fractionCompleted)
        }
      }
    }

    waitForExpectations(timeout: 20) { _ in
      observation?.invalidate()

      XCTAssertNotNil(filePath)
      XCTAssertTrue(FileManager.default.fileExists(atPath: filePath!.path))

      expectation = self.expectation(description: "Overwrite File")

      api.download(request, asFileName: "dummy.pdf", completion: { result in
        if case let .success(url) = result {
          filePath = url
          expectation.fulfill()
        }
      })

      self.waitForExpectations(timeout: 10) { _ in
        XCTAssertNotNil(filePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath!.path))
      }
    }
  }

  @available(iOS 13.0, *)
  func testAsyncAwait() async {
    let api = Api()
    let request = HttpRequest.get("https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf")

    do {
      let savedTo = try await api.download(request, asFileName: "dummy.pdf")
      XCTAssertEqual(savedTo.lastPathComponent, "dummy.pdf")
    } catch {
      XCTAssert(false)
    }
  }
}
