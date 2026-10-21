import Foundation

/// An immutable request builder. No work starts until `send` is called.
/// By default, HTTP status codes 200 through 299 are accepted.
public struct ApiCall {
  private let api: Api
  private let request: URLRequest
  private var validations: [ResponseValidation] = [.statusCode]

  init(api: Api, request: URLRequest) {
    self.api = api
    self.request = request
  }

  /// Returns a new builder with the supplied checks applied in order.
  /// Checks accumulate across calls. An explicit status check replaces the existing
  /// status check in place. `.none` clears all checks; later checks start a new policy.
  public func validating(_ checks: ResponseValidation...) -> ApiCall {
    var call = self
    for check in checks {
      switch check {
      case .none:
        call.validations.removeAll()
      case .statusCode:
        if let index = call.validations.firstIndex(where: {
          if case .statusCode = $0 {
            return true
          }
          return false
        }) {
          call.validations[index] = check
        } else {
          call.validations.append(check)
        }
      default:
        call.validations.append(check)
      }
    }
    return call
  }

  /// Sends the configured request and returns its cancellable operation.
  /// Checks run on the API's response queue after response interceptors.
  /// Responses handled by an interceptor bypass these checks.
  @discardableResult
  public func send(completion: HttpDataCompletion) -> HttpOperation {
    api.send(request, validations: validations, completion: completion)
  }

  /// Sends, validates, then decodes the body while retaining HTTP response information.
  @discardableResult
  public func send<T: Decodable>(decoder: DataDecoder? = nil, completion: HttpCompletion<T>) -> HttpOperation {
    let decoder = decoder ?? api.config.decoder
    return send { (result: Result<HttpDataResponse, Error>) in
      switch result {
      case let .success(response):
        do {
          let body = try decoder.decode(T.self, from: response.data)
          completion?(.success(HttpResponse(rawResponse: response, body: body)))
        } catch {
          completion?(.failure(ApiError.serializationFailed(error: error, response: response)))
        }
      case let .failure(error):
        completion?(.failure(error))
      }
    }
  }

  /// Sends, validates, and returns the decoded body.
  @discardableResult
  public func send<T: Decodable>(decoder: DataDecoder? = nil, completion: ApiCompletion<T>) -> HttpOperation {
    send(decoder: decoder) { (result: Result<HttpResponse<T>, Error>) in
      completion?(result.map { $0.body })
    }
  }
}

@available(iOS 13.0, *)
public extension ApiCall {
  func send() async throws -> HttpDataResponse {
    try await withCancellableOperation { completion in
      self.send(completion: completion)
    }
  }

  func send<T: Decodable>(decoder: DataDecoder? = nil) async throws -> HttpResponse<T> {
    try await withCancellableOperation { completion in
      self.send(decoder: decoder, completion: completion)
    }
  }

  func send<T: Decodable>(decoder: DataDecoder? = nil) async throws -> T {
    try await withCancellableOperation { completion in
      self.send(decoder: decoder, completion: completion)
    }
  }
}

public extension Api {
  /// Configures a request without enqueueing it. Status validation defaults to 200–299.
  func using(_ request: URLRequest) -> ApiCall {
    ApiCall(api: self, request: request)
  }

  /// Takes a snapshot of the request's URLRequest and returns a configurable builder.
  func using(_ request: HttpRequest) -> ApiCall {
    using(request.urlRequest)
  }

  /// Creates a request builder using `Api.default`.
  static func using(_ request: URLRequest) -> ApiCall {
    Api.default.using(request)
  }

  /// Creates a request builder using `Api.default`.
  static func using(_ request: HttpRequest) -> ApiCall {
    Api.default.using(request)
  }
}
