//
//  HttpOperation.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// Represents an HTTP network operation.
/// Cancelling completes the request once with `ApiError.cancelled`.
public class HttpOperation: Operation, @unchecked Sendable {
  /// The identifier used by interceptor callbacks and cancellation errors for this operation.
  public let id = UUID()

  /// Api configures these hooks before enqueueing the operation.
  typealias RequestModifier = (URLRequest, UUID, @escaping (URLRequest?) -> Void) -> Void
  /// Each modifier continues once with a request, or cancels by supplying nil.
  var requestModifiers: [RequestModifier] = []
  /// Return true to supply a response through completion instead of sending.
  var onWillSendRequest: ((URLRequest, UUID, @escaping RequiredHttpDataCompletion) -> Bool)?
  /// Forward or replace the result through completion; absent hooks pass it through.
  var onReceiveResponse: ((Result<HttpDataResponse, Error>, URLRequest, UUID, @escaping RequiredHttpDataCompletion) -> Void)?

  private var request: URLRequest
  private let session: URLSession
  private var completion: HttpDataCompletion
  private var urlSessionTask: URLSessionTask?
  private let lock = NSRecursiveLock()
  private let preparationQueue = DispatchQueue(label: "ApiKit.HttpOperation.preparation")
  private var hasStartedPreparation = false
  private var pendingModifierIndex: Int?
  private var hasCompleted = false
  private var _isExecuting = false
  private var _isFinished = false
  private var _onUrlSessionTask: ((URLSessionTask) -> Void)?

  public var onUrlSessionTask: ((URLSessionTask) -> Void)? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _onUrlSessionTask
    }
    set {
      lock.lock()
      _onUrlSessionTask = newValue
      lock.unlock()
    }
  }

  override public var isAsynchronous: Bool {
    true
  }

  override public var isExecuting: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isExecuting
  }

  override public var isFinished: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isFinished
  }

  init(request: URLRequest, session: URLSession = .shared, completion: HttpDataCompletion) {
    self.request = request
    self.session = session
    self.completion = completion
    super.init()
  }

  override public func start() {
    lock.lock()
    guard !_isFinished else {
      lock.unlock()
      return
    }
    if isCancelled {
      finishState()
      lock.unlock()
      return
    }
    willChangeValue(forKey: "isExecuting")
    _isExecuting = true
    didChangeValue(forKey: "isExecuting")
    lock.unlock()
    main()
  }

  override public func main() {
    lock.lock()
    guard !isCancelled, !hasCompleted, !hasStartedPreparation else {
      lock.unlock()
      return
    }
    hasStartedPreparation = true
    lock.unlock()
    preparationQueue.async { self.prepareRequest(at: 0) }
  }

  private func prepareRequest(at index: Int) {
    lock.lock()
    guard !isCancelled, !hasCompleted else {
      lock.unlock()
      return
    }
    let request = request
    if index < requestModifiers.count {
      let modify = requestModifiers[index]
      pendingModifierIndex = index
      lock.unlock()
      modify(request, id) { newRequest in
        self.preparationQueue.async { self.didModifyRequest(newRequest, at: index) }
      }
      return
    }
    let willSend = onWillSendRequest
    lock.unlock()

    if willSend?(request, id, { self.receive($0, for: request) }) == true {
      return
    }

    lock.lock()
    guard !isCancelled, !hasCompleted else {
      lock.unlock()
      return
    }
    lock.unlock()
    let task = session.dataTask(with: request) { data, response, error in
      let result: Result<HttpDataResponse, Error>
      if let error = error {
        result = .failure(error)
      } else if let response = response as? HTTPURLResponse {
        result = .success(HttpDataResponse(response: response, data: data ?? Data()))
      } else {
        result = .failure(ApiError.notHttpRequest)
      }
      self.receive(result, for: request)
    }

    // Register the task before resuming so cancellation cannot miss it.
    lock.lock()
    guard !isCancelled, !hasCompleted else {
      lock.unlock()
      task.cancel()
      return
    }
    urlSessionTask = task
    lock.unlock()
    onUrlSessionTask?(task)
    task.resume()
  }

  private func didModifyRequest(_ newRequest: URLRequest?, at index: Int) {
    lock.lock()
    guard !isCancelled, !hasCompleted, pendingModifierIndex == index else {
      lock.unlock()
      return
    }
    // Ignore repeated callbacks from a modifier, even if the next one is pending.
    pendingModifierIndex = nil
    guard let newRequest = newRequest else {
      lock.unlock()
      cancel()
      return
    }
    request = newRequest
    lock.unlock()
    prepareRequest(at: index + 1)
  }

  private func receive(_ result: Result<HttpDataResponse, Error>, for request: URLRequest) {
    lock.lock()
    guard !isCancelled, !hasCompleted else {
      lock.unlock()
      return
    }
    let receiveResponse = onReceiveResponse
    lock.unlock()
    if let receiveResponse = receiveResponse {
      receiveResponse(result, request, id) { self.complete($0) }
    } else {
      complete(result)
    }
  }

  private func complete(_ result: Result<HttpDataResponse, Error>) {
    lock.lock()
    guard !hasCompleted else {
      lock.unlock()
      return
    }
    hasCompleted = true
    let result = isCancelled ? .failure(ApiError.cancelled(request: request, id: id)) : result
    let completion = completion
    self.completion = nil
    if _isExecuting {
      finishState()
    } else {
      // A queued operation transitions to finished when its queue starts it.
      releaseResources()
    }
    lock.unlock()
    completion?(result)
  }

  private func releaseResources() {
    urlSessionTask = nil
    requestModifiers = []
    onWillSendRequest = nil
    onReceiveResponse = nil
    pendingModifierIndex = nil
  }

  /// Called with lock held; KVO observers may read the state recursively.
  private func finishState() {
    guard !_isFinished else { return }
    willChangeValue(forKey: "isFinished")
    let wasExecuting = _isExecuting
    if wasExecuting {
      willChangeValue(forKey: "isExecuting")
    }
    _isExecuting = false
    _isFinished = true
    releaseResources()
    if wasExecuting {
      didChangeValue(forKey: "isExecuting")
    }
    didChangeValue(forKey: "isFinished")
  }

  override public func cancel() {
    lock.lock()
    guard !hasCompleted, !isCancelled else {
      lock.unlock()
      return
    }
    super.cancel()
    let task = urlSessionTask
    let error = ApiError.cancelled(request: request, id: id)
    lock.unlock()
    task?.cancel()
    complete(.failure(error))
  }
}

/// Handles cancellation that arrives before an async request returns its operation.
final class HttpOperationCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var operation: HttpOperation?
  private var isCancelled = false

  func register(_ operation: HttpOperation?) {
    lock.lock()
    self.operation = operation
    let shouldCancel = isCancelled
    lock.unlock()
    if shouldCancel {
      operation?.cancel()
    }
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    let operation = operation
    lock.unlock()
    operation?.cancel()
  }
}
