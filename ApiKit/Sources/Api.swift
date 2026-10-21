import Foundation

typealias RequiredHttpDataCompletion = (Result<HttpDataResponse, Error>) -> Void
/// A callback that provides a Result which contains the decode body.
public typealias ApiCompletion<T: Decodable> = ((Result<T, Error>) -> Void)?
/// A callback that provides a Result which contains a RawHttpResponse with its raw body.
public typealias HttpDataCompletion = ((Result<HttpDataResponse, Error>) -> Void)?
/// A callback that provides a Result which contains a HttpResponse with its decode body.
public typealias HttpCompletion<T: Decodable> = ((Result<HttpResponse<T>, Error>) -> Void)?

/// Simplifies HTTP networking making it easy to call cloud APIs
open class Api {
  /// A default instance of Api which was initialized using URLSession.shared and DefaultApiConfig.
  public static let `default` = Api()

  /// Configuration information for the API
  public var config: ApiConfig
  /// The URLSession that is used when making network requests.
  public let urlSession: URLSession

  /// Creates an instance of Api using an ApiConfig
  /// - Parameter config: The configuration information that the Api will use.
  public convenience init(config: ApiConfig? = nil) {
    self.init(urlSession: URLSession.shared, config: config)
  }

  /// Creates an instance of Api using an ApiConfig and URLSession
  /// - Parameters:
  ///   - urlSession: The URLSession that is used when making network requests.
  ///   - config: The configuration information that the Api will use.
  public init(urlSession: URLSession, config: ApiConfig? = nil) {
    self.urlSession = urlSession
    self.config = config ?? DefaultApiConfig()
  }

  private func combining(_ a: [String: String], _ b: [String: String]) -> [String: String] {
    return a.merging(b, uniquingKeysWith: config.headerConflictHandler)
  }

  /// Similiar to `send` but this will save the response body data to a file.
  /// - Parameters:
  ///   - request: The request to send.
  ///   - dir: The directory to save the file too.
  ///   - fileName: The name of the file that will be downloaded.
  ///   - completion: Called when the request was completed either successful or not.
  /// - Returns: An HttpOperation that can be used to cancel this operation.
  @discardableResult
  public func download(_ request: URLRequest, to dir: URL? = nil, asFileName fileName: String, completion: @escaping (Result<URL, Error>) -> Void) -> HttpOperation? {
    return send(request) { result in
      switch result {
      case let .success(response):
        let data = response.data

        let fileManager = FileManager.default

        let directory = dir ?? fileManager.temporaryDirectory
        let saveToURL = directory.appendingPathComponent(fileName)
        do {
          try data.write(to: saveToURL, options: .atomic)
          completion(.success(saveToURL))
        } catch {
          completion(.failure(error))
        }
      case let .failure(err):
        completion(.failure(err))
      }
    }
  }

  private func executeInceptor(execution: (ApiInterceptor) -> Bool) -> Bool {
    for interceptor in config.interceptors {
      if execution(interceptor) {
        return true
      }
    }
    return false
  }

  /// Sends a request.
  /// This completion gives a HttpDataResponse so properties like status code, response body, etc can be accessed.
  /// - Parameters:
  ///   - request: The request to send
  ///   - completion: Called when the request was completed either successful or unsuccessfully.
  /// - Returns: An HttpOperation that can be used to cancel this operation.
  @discardableResult
  public func send(_ request: URLRequest, completion: HttpDataCompletion) -> HttpOperation {
    send(request, validations: [.statusCode], completion: completion)
  }

  func send(_ request: URLRequest, validations: [ResponseValidation], completion: HttpDataCompletion) -> HttpOperation {
    let responseQueue = config.responseQueue
    let operation = HttpOperation(request: request, session: urlSession) { result in
      responseQueue.addOperation { completion?(result) }
    }
    operation.requestModifiers = config.interceptors.map { interceptor in
      return { request, id, proceed in
        interceptor.api(self, modifyRequest: request, withId: id, onNewRequest: proceed)
      }
    }
    operation.onWillSendRequest = { request, id, complete in
      self.executeInceptor {
        $0.api(self, willSendRequest: request, withId: id, completion: complete)
      }
    }
    operation.onReceiveResponse = { [weak operation] result, request, id, complete in
      responseQueue.addOperation {
        guard let operation = operation, !operation.isCancelled, !operation.isFinished else { return }
        let wasIntercepted = self.executeInceptor {
          $0.api(self, didReceive: result, withId: id, for: request, completion: complete)
        }
        guard !wasIntercepted else { return }
        do {
          if case let .success(response) = result {
            for validation in validations { try validation.validate(response) }
          }
          complete(result)
        } catch {
          complete(.failure(error))
        }
      }
    }

    config.requestQueue.addOperation(operation)
    return operation
  }
}

public extension Api {
  /// Creates a URLRequest for HTTP / HTTPs protocols
  /// - Parameters:
  ///   - url: The url the request will be sent too.
  ///   - method: The HTTP method that will be used.
  ///   - headers: The headers to include if any.
  /// - Returns: A URLRequest that can be sent via Api
  func request(with url: URL, method: HttpMethod, headers: [String: String] = [:]) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method.rawValue
    request.allHTTPHeaderFields = headers
    return request
  }

  /// Creates a URLRequest for HTTP / HTTPs protocols
  /// - Parameters:
  ///   - url: The url the request will be sent too.
  ///   - method: The HTTP method that will be used.
  ///   - headers: The headers to include if any.
  /// - Returns: A URLRequest that can be sent via Api
  func request(with url: String, method: HttpMethod, headers: [String: String] = [:]) -> URLRequest {
    guard let url = URL(string: url) else {
      fatalError("Invalid URL")
    }
    return request(with: url, method: method, headers: headers)
  }

  /// Creates a URLRequest for HTTP / HTTPs protocols
  /// - Parameters:
  ///   - host: The host or base url.
  ///   - path: The path that be appended to the host.
  ///   - method: The HTTP method that will be used.
  ///   - headers: The headers to include if any.
  /// - Returns: A URLRequest that can be sent via Api
  func request(host: String, path: String, method: HttpMethod, headers: [String: String] = [:]) -> URLRequest {
    return request(with: "\(host)\(path)", method: method, headers: headers)
  }

  /// Creates a URLRequest for HTTP / HTTPs protocols
  /// - Parameters:
  ///   - endpoint: The endpoint information which includes a url and headers.
  ///   - path: The path that be appended to the endpoint url.
  ///   - method: The HTTP method that will be used.
  ///   - headers: The headers to include if any.
  /// - Returns: A URLRequest that can be sent via Api
  func request(endpoint: EndpointInfo, path: String, method: HttpMethod, headers: [String: String] = [:]) -> URLRequest {
    return request(host: endpoint.url,
                   path: path,
                   method: method,
                   headers: combining(headers, endpoint.headers))
  }
}

public extension URLRequest {
  @discardableResult
  mutating func add(rawBody: Data) -> URLRequest {
    httpBody = rawBody
    return self
  }

  @discardableResult
  mutating func add<T: Encodable>(encodable: T, encoder: DataEncoder = JSONEncoder(), mimeType: String = "application/json") throws -> URLRequest {
    let data = try encoder.encode(encodable)
    setValue(mimeType, forHTTPHeaderField: "Content-Type")
    return add(rawBody: data)
  }
}

public extension Api {
  /// Sends a request and decodes response body using provided DataDecoder or the default decoder from ApiConfig.
  /// This completion does gives the HttpResponse so properties like status code, etc can be accessed.
  /// - Parameters:
  ///   - request: The request to send
  ///   - decoder: The optional decoder used to decode the response body. If nil then the default decoder from ApiConfig is used.
  ///   - completion: Called when the request was completed either successful or unsuccessfully.
  /// - Returns: An HttpOperation that can be used to cancel this operation.
  @discardableResult
  func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil, completion: HttpCompletion<T>) -> HttpOperation? {
    using(request).send(decoder: decoder, completion: completion)
  }

  /// Sends a request and decodes response body using provided DataDecoder or the default decoder from ApiConfig.
  /// This completion does not given any response information like status code, etc.
  /// - Parameters:
  ///   - request: The request to send
  ///   - decoder: The optional decoder used to decode the response body. If nil then the default decoder from ApiConfig is used.
  ///   - completion: Called when the request was completed either successful or unsuccessfully.
  /// - Returns: An HttpOperation that can be used to cancel this operation.
  @discardableResult
  func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil, completion: ApiCompletion<T>) -> HttpOperation? {
    using(request).send(decoder: decoder, completion: completion)
  }
}

public extension Api {
  @discardableResult
  static func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil, completion: ApiCompletion<T>) -> HttpOperation? {
    return Api.default.send(request, decoder: decoder, completion: completion)
  }

  @discardableResult
  static func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil, completion: HttpCompletion<T>) -> HttpOperation? {
    return Api.default.send(request, decoder: decoder, completion: completion)
  }

  @discardableResult
  static func send(_ request: URLRequest, completion: HttpDataCompletion) -> HttpOperation {
    return Api.default.send(request, completion: completion)
  }

  @discardableResult
  static func download(_ request: URLRequest, to dir: URL? = nil, asFileName fileName: String, completion: @escaping (Result<URL, Error>) -> Void) -> HttpOperation? {
    return Api.default.download(request, to: dir, asFileName: fileName, completion: completion)
  }
}

@available(iOS 13.0, *)
public extension Api {
  func send(_ request: URLRequest) async throws -> HttpDataResponse {
    try await withCancellableOperation { completion in
      self.send(request, completion: completion)
    }
  }

  func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil) async throws -> HttpResponse<T> {
    try await withCancellableOperation { completion in
      self.send(request, decoder: decoder, completion: completion)
    }
  }

  func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil) async throws -> T {
    try await withCancellableOperation { completion in
      self.send(request, decoder: decoder, completion: completion)
    }
  }

  func download(_ request: URLRequest, to dir: URL? = nil, asFileName fileName: String) async throws -> URL {
    try await withCancellableOperation { completion in
      self.download(request, to: dir, asFileName: fileName, completion: completion)
    }
  }
}

@available(iOS 13.0, *)
extension Api {
  static func send(_ request: URLRequest) async throws -> HttpDataResponse {
    try await Api.default.send(request)
  }

  static func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil) async throws -> HttpResponse<T> {
    try await Api.default.send(request, decoder: decoder)
  }

  static func send<T: Decodable>(_ request: URLRequest, decoder: DataDecoder? = nil) async throws -> T {
    try await Api.default.send(request, decoder: decoder)
  }
}

@available(iOS 13.0, *)
func withCancellableOperation<T>(
  _ start: (@escaping (Result<T, Error>) -> Void) -> HttpOperation?
) async throws -> T {
  let cancellation = HttpOperationCancellation()
  return try await withTaskCancellationHandler(operation: {
    try Task.checkCancellation()
    return try await withCheckedThrowingContinuation { continuation in
      cancellation.register(start { result in
        continuation.resume(with: result)
      })
    }
  }, onCancel: {
    cancellation.cancel()
  })
}
