//
//  HttpRequest.swift
//
//
//  Created by Nicholas Mata on 6/15/22.
//

import Foundation

/// A wrapper around URLRequest for easy access to important information and better initializers
public class HttpRequest {
  private static func combining(_ a: [String: String], _ b: [String: String]) -> [String: String] {
    return a.merging(b, uniquingKeysWith: HttpRequest.headerConflictHandler)
  }

  public static var headerConflictHandler: (String, String) -> String = { a, _ in
    a
  }

  /// The url the request will be sent too.
  public var url: URL
  /// The HTTP method that the request will use.
  public var method: HttpMethod
  /// The headers that will be included in the request.
  public var headers: [String: String] = [:]
  /// The raw request body as data that will be sent.
  public var body: Data?

  /// A URLRequest which is equalivant to this ApiRequest.
  public var urlRequest: URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.allHTTPHeaderFields = headers
    request.httpBody = body
    return request
  }

  /// Initializes an HttpRequest
  /// - Parameters:
  ///   - url: The url the request will be sent too.
  ///   - method: The HTTP method that the request will use.
  ///   - headers: The headers that will be included in the request.
  ///   - rawBody: The raw request body as data that will be sent.
  public init(url: URL, method: HttpMethod, headers: [String: String] = [:], rawBody: Data? = nil) {
    self.url = url
    self.method = method
    self.headers = headers
    body = rawBody
  }

  /// Initializes an HttpRequest
  /// - Parameters:
  ///   - url: The url the request will be sent too.
  ///   - method: The HTTP method that the request will use.
  ///   - headers: The headers that will be included in the request.
  ///   - rawBody: The raw request body as data that will be sent.
  public convenience init(url: String, method: HttpMethod,
                          headers: [String: String] = [:], rawBody: Data? = nil)
  {
    guard let url = URL(string: url) else {
      fatalError("Invalid URL")
    }
    self.init(url: url, method: method, headers: headers, rawBody: rawBody)
  }

  /// Initializes an HttpRequest
  /// - Parameters:
  ///   - host: The host or base url.
  ///   - path: The path that be appended to the host.
  ///   - method: The HTTP method that the request will use.
  ///   - headers: The headers that will be included in the request.
  ///   - rawBody: The raw request body as data that will be sent.
  public convenience init(host: String, path: String, method: HttpMethod,
                          headers: [String: String] = [:], rawBody: Data? = nil)
  {
    self.init(url: "\(host)\(path)", method: method, headers: headers, rawBody: rawBody)
  }

  /// Initializes an HttpRequest
  /// - Parameters:
  ///   - endpoint: The endpoint information which includes a url and headers.
  ///   - path: The path that be appended to the endpoint url.
  ///   - method: The HTTP method that the request will use.
  ///   - headers: The headers that will be included in the request.
  ///   - rawBody: The raw request body as data that will be sent.
  public convenience init(endpoint: EndpointInfo, path: String, method: HttpMethod, headers: [String: String] = [:], rawBody: Data? = nil) {
    self.init(host: endpoint.url, path: path, method: method, headers: HttpRequest.combining(headers, endpoint.headers), rawBody: rawBody)
  }
}

public extension HttpRequest {
  static func get(endpoint: EndpointInfo, path: String, headers: [String: String] = [:]) -> HttpRequest {
    return HttpRequest(endpoint: endpoint, path: path, method: .get, headers: headers)
  }

  static func get(host: String, path: String, headers: [String: String] = [:]) -> HttpRequest {
    return HttpRequest(host: host, path: path, method: .get, headers: headers)
  }

  static func get(_ url: URL, headers: [String: String] = [:]) -> HttpRequest {
    return HttpRequest(url: url, method: .get, headers: headers)
  }

  static func get(_ url: String, headers: [String: String] = [:]) -> HttpRequest {
    return HttpRequest(url: url, method: .get, headers: headers)
  }
}

public extension HttpRequest {
  convenience init<T: Encodable>(url: URL, method: HttpMethod,
                                 headers: [String: String] = [:],
                                 body: T? = nil,
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws
  {
    let rawBody = try encoder.encode(body)
    var headers = headers
    headers["Content-Type"] = contentType
    self.init(url: url, method: method, headers: headers, rawBody: rawBody)
  }

  convenience init<T: Encodable>(url: String, method: HttpMethod,
                                 headers: [String: String] = [:],
                                 body: T? = nil,
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws
  {
    guard let url = URL(string: url) else {
      fatalError("Invalid URL")
    }
    try self.init(url: url, method: method, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  convenience init<T: Encodable>(host: String,
                                 path: String,
                                 method: HttpMethod,
                                 headers: [String: String] = [:],
                                 body: T? = nil,
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws
  {
    try self.init(url: "\(host)\(path)", method: method, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  convenience init<T: Encodable>(endpoint: EndpointInfo,
                                 path: String,
                                 method: HttpMethod,
                                 headers: [String: String] = [:],
                                 body: T? = nil,
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws
  {
    try self.init(host: endpoint.url, path: path, method: method, headers: HttpRequest.combining(headers, endpoint.headers), body: body, encoder: encoder, contentType: contentType)
  }

  static func post(endpoint: EndpointInfo, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(endpoint: endpoint, path: path, method: .post, headers: headers, rawBody: rawBody)
  }

  static func post(host: String, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(host: host, path: path, method: .post, headers: headers, rawBody: rawBody)
  }

  static func post(_ url: URL, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .post, headers: headers, rawBody: rawBody)
  }

  static func post(_ url: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .post, headers: headers, rawBody: rawBody)
  }

  static func post<T: Encodable>(endpoint: EndpointInfo, path: String, body: T, headers: [String: String] = [:],
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(endpoint: endpoint, path: path, method: .post, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func post<T: Encodable>(host: String, path: String, body: T, headers: [String: String] = [:],
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(host: host, path: path, method: .post, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func post<T: Encodable>(_ url: String, body: T, headers: [String: String] = [:],
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .post, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func post<T: Encodable>(_ url: URL, body: T, headers: [String: String] = [:],
                                 encoder: DataEncoder = JSONEncoder(),
                                 contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .post, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }
}

public extension HttpRequest {
  static func put(endpoint: EndpointInfo, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(endpoint: endpoint, path: path, method: .put, headers: headers, rawBody: rawBody)
  }

  static func put(host: String, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(host: host, path: path, method: .put, headers: headers, rawBody: rawBody)
  }

  static func put(_ url: URL, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .put, headers: headers, rawBody: rawBody)
  }

  static func put(_ url: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .put, headers: headers, rawBody: rawBody)
  }

  static func put<T: Encodable>(endpoint: EndpointInfo, path: String, body: T, headers: [String: String] = [:],
                                encoder: DataEncoder = JSONEncoder(),
                                contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(endpoint: endpoint, path: path, method: .put, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func put<T: Encodable>(host: String, path: String, body: T, headers: [String: String] = [:],
                                encoder: DataEncoder = JSONEncoder(),
                                contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(host: host, path: path, method: .put, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func put<T: Encodable>(_ url: String, body: T, headers: [String: String] = [:],
                                encoder: DataEncoder = JSONEncoder(),
                                contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .put, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func put<T: Encodable>(_ url: URL, body: T, headers: [String: String] = [:],
                                encoder: DataEncoder = JSONEncoder(),
                                contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .put, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }
}

public extension HttpRequest {
  static func patch(endpoint: EndpointInfo, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(endpoint: endpoint, path: path, method: .patch, headers: headers, rawBody: rawBody)
  }

  static func patch(host: String, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(host: host, path: path, method: .patch, headers: headers, rawBody: rawBody)
  }

  static func patch(_ url: URL, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .patch, headers: headers, rawBody: rawBody)
  }

  static func patch(_ url: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .patch, headers: headers, rawBody: rawBody)
  }

  static func patch<T: Encodable>(endpoint: EndpointInfo, path: String, body: T, headers: [String: String] = [:],
                                  encoder: DataEncoder = JSONEncoder(),
                                  contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(endpoint: endpoint, path: path, method: .patch, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func patch<T: Encodable>(host: String, path: String, body: T, headers: [String: String] = [:],
                                  encoder: DataEncoder = JSONEncoder(),
                                  contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(host: host, path: path, method: .patch, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func patch<T: Encodable>(_ url: String, body: T, headers: [String: String] = [:],
                                  encoder: DataEncoder = JSONEncoder(),
                                  contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .patch, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func patch<T: Encodable>(_ url: URL, body: T, headers: [String: String] = [:],
                                  encoder: DataEncoder = JSONEncoder(),
                                  contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .patch, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }
}

public extension HttpRequest {
  static func delete(endpoint: EndpointInfo, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(endpoint: endpoint, path: path, method: .delete, headers: headers, rawBody: rawBody)
  }

  static func delete(host: String, path: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(host: host, path: path, method: .delete, headers: headers, rawBody: rawBody)
  }

  static func delete(_ url: URL, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .delete, headers: headers, rawBody: rawBody)
  }

  static func delete(_ url: String, rawBody: Data? = nil, headers: [String: String] = [:]) -> HttpRequest {
    HttpRequest(url: url, method: .delete, headers: headers, rawBody: rawBody)
  }

  static func delete<T: Encodable>(endpoint: EndpointInfo, path: String, body: T, headers: [String: String] = [:],
                                   encoder: DataEncoder = JSONEncoder(),
                                   contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(endpoint: endpoint, path: path, method: .delete, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func delete<T: Encodable>(host: String, path: String, body: T, headers: [String: String] = [:],
                                   encoder: DataEncoder = JSONEncoder(),
                                   contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(host: host, path: path, method: .delete, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func delete<T: Encodable>(_ url: String, body: T, headers: [String: String] = [:],
                                   encoder: DataEncoder = JSONEncoder(),
                                   contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .delete, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }

  static func delete<T: Encodable>(_ url: URL, body: T, headers: [String: String] = [:],
                                   encoder: DataEncoder = JSONEncoder(),
                                   contentType: String = "application/json") throws -> HttpRequest
  {
    try HttpRequest(url: url, method: .delete, headers: headers, body: body, encoder: encoder, contentType: contentType)
  }
}

public extension Api {
  @discardableResult
  func download(_ request: HttpRequest, to dir: URL? = nil, asFileName fileName: String, completion: @escaping (Result<URL, Error>) -> Void) -> HttpOperation? {
    return download(request.urlRequest, to: dir, asFileName: fileName, completion: completion)
  }

  @discardableResult
  func send(_ request: HttpRequest, completion: HttpDataCompletion) -> HttpOperation? {
    return send(request.urlRequest, completion: completion)
  }

  @discardableResult
  func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil, completion: HttpCompletion<T>) -> HttpOperation? {
    return send(request.urlRequest, decoder: decoder, completion: completion)
  }

  @discardableResult
  func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil, completion: ApiCompletion<T>) -> HttpOperation? {
    return send(request.urlRequest, decoder: decoder, completion: completion)
  }
}

public extension Api {
  @discardableResult
  static func download(_ request: HttpRequest, to dir: URL? = nil, asFileName fileName: String, completion: @escaping (Result<URL, Error>) -> Void) -> HttpOperation? {
    return Api.default.download(request.urlRequest, to: dir, asFileName: fileName, completion: completion)
  }

  @discardableResult
  static func send(_ request: HttpRequest, completion: HttpDataCompletion) -> HttpOperation? {
    return Api.default.send(request.urlRequest, completion: completion)
  }

  @discardableResult
  static func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil, completion: HttpCompletion<T>) -> HttpOperation? {
    return Api.default.send(request.urlRequest, decoder: decoder, completion: completion)
  }

  @discardableResult
  static func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil, completion: ApiCompletion<T>) -> HttpOperation? {
    return Api.default.send(request.urlRequest, decoder: decoder, completion: completion)
  }
}


@available(iOS 13.0, *)
public extension Api {
  func send(_ request: HttpRequest) async throws -> HttpDataResponse {
    try await send(request.urlRequest)
  }

  func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil) async throws -> HttpResponse<T> {
    try await send(request.urlRequest, decoder: decoder)
  }

  func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil) async throws -> T {
    try await send(request.urlRequest, decoder: decoder)
  }

  func download(_ request: HttpRequest, to dir: URL? = nil, asFileName fileName: String) async throws -> URL {
    try await download(request.urlRequest, to: dir, asFileName: fileName)
  }
}

@available(iOS 13.0, *)
public extension Api {
  static func send(_ request: HttpRequest) async throws -> HttpDataResponse {
    try await Api.default.send(request.urlRequest)
  }

  static func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil) async throws -> HttpResponse<T> {
    try await Api.default.send(request.urlRequest, decoder: decoder)
  }

  static func send<T: Decodable>(_ request: HttpRequest, decoder: DataDecoder? = nil) async throws -> T {
    try await Api.default.send(request.urlRequest, decoder: decoder)
  }

  static func download(_ request: HttpRequest, to dir: URL? = nil, asFileName fileName: String) async throws -> URL {
    try await Api.default.download(request.urlRequest, to: dir, asFileName: fileName)
  }
}

