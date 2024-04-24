//
//  ApiSerializationTests.swift
//
//
//  Created by Nicholas Mata on 4/18/24.
//

import ApiKit
import XCTest

public struct TestObject: Encodable {
  var string: String = "testing"

  var int: Int = -1
  var uint: UInt = 1
  var float: Float = 1.1
  var double: Double = 1.1

  var date: Date = .init()
}

final class ApiSerializationTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testURLEncodingSerialiation() throws {
      let encoder = URLEncodedFormEncoder(arrayEncoding: .indexInBrackets,
                                          dateEncoding: .iso8601)
      let now = Date()
      let nowISO8601 = ISO8601DateFormatter().string(from: now)
      let request = try HttpRequest.post("https://testing.com",
                                         body: TestObject(date: now),
                                         encoder: encoder)
      guard let body = request.body else {
        XCTAssert(false, "Request must have a body.")
        return
      }
      let requestBody = String(decoding: body, as: UTF8.self)
      guard let requestBodyNoPercents = requestBody.removingPercentEncoding else {
        XCTAssert(false, "Unable to remove percent encoding")
        return
      }
      XCTAssertEqual("date=\(nowISO8601)&double=1.1&float=1.1&int=-1&string=testing&uint=1", requestBodyNoPercents)
    }
}
