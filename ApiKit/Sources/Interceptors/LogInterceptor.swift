//
//  LogInterceptor.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// The level of logging for LogInterceptor
public enum LogLevel {
  /// The most detailed logs this includes request and response body as strings.
  case verbose
  /// The least detailed logs does not include request and response body.
  case info
}

/// Used to log all requests and response from the API.
open class LogInterceptor: ApiInterceptor {
  public var level: LogLevel
  public init(level: LogLevel = .info) {
    self.level = level
  }

  private var durations: [UUID: CFAbsoluteTime] = [:]
  private var semaphore = DispatchSemaphore(value: 1)

  public func api(_: Api, modifyRequest request: URLRequest, withId identifier: UUID, onNewRequest: @escaping (URLRequest) -> Void) {
    let now = CFAbsoluteTimeGetCurrent()
    semaphore.wait()
    durations[identifier] = now
    semaphore.signal()
    onNewRequest(request)
  }

  public func api(_: Api, didReceive result: Result<HttpDataResponse, Error>, withId identifier: UUID, for request: URLRequest, completion _: HttpDataCompletion) -> Bool {
    let now = CFAbsoluteTimeGetCurrent()
    semaphore.wait()
    let start = durations[identifier] ?? now
    durations.removeValue(forKey: identifier)
    semaphore.signal()

    var messages: [String] = []
    messages.append("""
    ID: \(identifier)
    Took: \(now - start) seconds
    """)

    var requestMessage = """
    \(request.httpMethod ?? "No Method") \(request.url?.absoluteString ?? "Unknown URL")
    """
    if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
      let headerString = headers.toReadableString()
      requestMessage += "\n \n\(headerString)"
    }
    if level == .verbose, let requestBody = request.httpBody, let requestBodyString = String(data: requestBody, encoding: .utf8) {
      requestMessage += "\n \n\(requestBodyString)"
    }
    messages.append(requestMessage)
    var responseMessage = ""
    switch result {
    case let .success(response):
      responseMessage += "StatusCode: \(response.successful ? "✅" : "❗️") \(response.statusCode)"
      
      if level == .verbose {
        let headers = response.allHeaderFields
        let headerString = headers.toReadableString()
        responseMessage += "\n \n\(headerString)"
      }

      if level == .verbose, let responseBodyString = String(data: response.data, encoding: .utf8) {
        responseMessage += "\n \n\(responseBodyString)"
      }
    case let .failure(err):
      responseMessage += """
      Failed: "\(err.localizedDescription)"
      """
    }
    messages.append(responseMessage)

    print(sections: messages)

    return false
  }

  private func print(sections: [String], prefix _: String = "=", suffix _: String = "=", separator _: String = "-") {
    let absoluteMaxLineCount = 100
    let maxLineCount = min(sections.reduce(into: []) { partialResult, section in
      partialResult.append(contentsOf: section.split(separator: "\n"))
    }.max(by: { $1.count > $0.count })?.count ?? 1, absoluteMaxLineCount)

    var message = ""
    sections.enumerated().forEach { element in
      let section = element.element
      var bottom: String? = "-"
      if element.offset == (sections.count - 1) {
        bottom = nil
      }
      message += section.boxed(top: nil, bottom: bottom, largestLine: min(maxLineCount, absoluteMaxLineCount-2)) + "\n"
    }
    Swift.print(message.boxed(largestLine: maxLineCount))
  }
}

extension Dictionary {
  func toReadableString() -> String {
    return self.map { String(describing: $0.0) + ": " + String(describing: $0.1) }.joined(separator: "\n")
  }
}
