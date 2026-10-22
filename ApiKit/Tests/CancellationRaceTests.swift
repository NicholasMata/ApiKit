@testable import ApiKit
import XCTest

final class CancellationRaceTests: XCTestCase {
  func testConcurrentCancellationAndResponsesCompleteEachOperationOnce() {
    let count = 100
    let ready = expectation(description: "All operations wait for responses")
    ready.expectedFulfillmentCount = count
    let completed = expectation(description: "Each operation completes once")
    completed.expectedFulfillmentCount = count
    completed.assertForOverFulfill = true
    let callbacks = LockedCallbacks(count: count)
    let counts = LockedCounts(count: count)
    let request = URLRequest(url: URL(string: "https://apikit.test/race")!)
    let operations = (0 ..< count).map { index in
      let operation = HttpOperation(request: request) { result in
        if case .success = result { XCTFail("Expected cancellation or fixture error") }
        counts.increment(index)
        completed.fulfill()
      }
      operation.onWillSendRequest = { _, _, complete in
        callbacks.set(complete, at: index)
        ready.fulfill()
        return true
      }
      operation.start()
      return operation
    }
    wait(for: [ready], timeout: 10)
    DispatchQueue.concurrentPerform(iterations: count * 4) { index in
      let operationIndex = index / 4
      if index.isMultiple(of: 2) {
        operations[operationIndex].cancel()
      } else {
        callbacks.get(operationIndex)?(.failure(URLError(.timedOut)))
      }
    }
    wait(for: [completed], timeout: 10)
    XCTAssertEqual(counts.snapshot, Array(repeating: 1, count: count))
    XCTAssertTrue(operations.allSatisfy { $0.isFinished && !$0.isExecuting })
  }

  func testConcurrentResponseCompletionsDeliverOneResult() {
    let intercepted = expectation(description: "Response hook is waiting")
    let completed = expectation(description: "One final completion")
    completed.assertForOverFulfill = true
    let callbacks = LockedCallbacks(count: 1)
    let counts = LockedCounts(count: 1)
    let operation = HttpOperation(request: URLRequest(url: URL(string: "https://apikit.test")!)) { _ in
      counts.increment(0)
      completed.fulfill()
    }
    operation.onWillSendRequest = { _, _, complete in
      complete(.failure(URLError(.timedOut)))
      return true
    }
    operation.onReceiveResponse = { _, _, _, complete in
      callbacks.set(complete, at: 0)
      intercepted.fulfill()
    }
    operation.start()
    wait(for: [intercepted], timeout: 5)
    DispatchQueue.concurrentPerform(iterations: 100) { _ in
      callbacks.get(0)?(.failure(URLError(.cannotConnectToHost)))
    }
    wait(for: [completed], timeout: 5)
    XCTAssertEqual(counts.snapshot, [1])
    XCTAssertTrue(operation.isFinished)
  }

  func testCancelledCompletionUsesConfiguredResponseQueue() {
    let responseQueue = OperationQueue()
    responseQueue.name = "CancellationRaceTests.responses"
    let requestQueue = OperationQueue()
    requestQueue.isSuspended = true
    defer { requestQueue.isSuspended = false }
    let api = Api(config: DefaultApiConfig(requestQueue: requestQueue, responseQueue: responseQueue))
    let completed = expectation(description: "Cancellation on response queue")
    let operation = api.send(URLRequest(url: URL(string: "https://apikit.test")!)) { result in
      XCTAssertTrue(OperationQueue.current === responseQueue)
      if case .failure(ApiError.cancelled) = result {} else { XCTFail("Expected cancellation") }
      completed.fulfill()
    }
    operation.cancel()
    wait(for: [completed], timeout: 5)
  }

  func testCancellingQueuedDependencyAllowsDependentOperationToRun() {
    let queue = OperationQueue()
    queue.isSuspended = true
    let completed = expectation(description: "Cancelled operation completes")
    let operation = HttpOperation(request: URLRequest(url: URL(string: "https://apikit.test")!)) { result in
      if case .failure(ApiError.cancelled) = result {} else { XCTFail("Expected cancellation") }
      completed.fulfill()
    }
    let dependentFinished = expectation(description: "Dependent operation runs")
    let dependent = BlockOperation {
      XCTAssertTrue(operation.isFinished)
      dependentFinished.fulfill()
    }
    dependent.addDependency(operation)
    queue.addOperations([operation, dependent], waitUntilFinished: false)
    operation.cancel()
    queue.isSuspended = false
    wait(for: [completed, dependentFinished], timeout: 5)
  }

  func testAsyncCancellationRegistrationRaceNeverLosesCancellation() {
    let completed = expectation(description: "Every registration race cancels")
    completed.expectedFulfillmentCount = 100
    completed.assertForOverFulfill = true
    for _ in 0 ..< 100 {
      let cancellation = HttpOperationCancellation()
      let operation = HttpOperation(request: URLRequest(url: URL(string: "https://apikit.test")!)) { result in
        if case .failure(ApiError.cancelled) = result {} else { XCTFail("Expected cancellation") }
        completed.fulfill()
      }
      DispatchQueue.concurrentPerform(iterations: 2) { index in
        if index == 0 { cancellation.register(operation) } else { cancellation.cancel() }
      }
      operation.start()
      XCTAssertTrue(operation.isCancelled)
      XCTAssertTrue(operation.isFinished)
    }
    wait(for: [completed], timeout: 5)
  }
}

private final class LockedCallbacks {
  private let lock = NSLock()
  private var callbacks: [RequiredHttpDataCompletion?]
  init(count: Int) { callbacks = Array(repeating: nil, count: count) }
  func set(_ callback: @escaping RequiredHttpDataCompletion, at index: Int) {
    lock.lock()
    callbacks[index] = callback
    lock.unlock()
  }
  func get(_ index: Int) -> RequiredHttpDataCompletion? {
    lock.lock()
    defer { lock.unlock() }
    return callbacks[index]
  }
}

private final class LockedCounts {
  private let lock = NSLock()
  private var counts: [Int]
  init(count: Int) { counts = Array(repeating: 0, count: count) }
  func increment(_ index: Int) {
    lock.lock()
    counts[index] += 1
    lock.unlock()
  }
  var snapshot: [Int] {
    lock.lock()
    defer { lock.unlock() }
    return counts
  }
}
