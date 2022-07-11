//
//  HttpOperation.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// Represents an HTTP network operation.
public class HttpOperation: Operation {
  private var block: (HttpOperation) -> URLSessionTask?
  private var urlSessionTask: URLSessionTask?

  private let lockQueue = DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).lock-queue", attributes: .concurrent)
  
  public var onUrlSessionTask: ((URLSessionTask) -> Void)? = nil

  override public var isAsynchronous: Bool {
    return true
  }

  private var _isExecuting: Bool = false
  override public private(set) var isExecuting: Bool {
    get {
      return lockQueue.sync { () -> Bool in
        _isExecuting
      }
    }
    set {
      willChangeValue(forKey: "isExecuting")
      lockQueue.sync(flags: [.barrier]) {
        _isExecuting = newValue
      }
      didChangeValue(forKey: "isExecuting")
    }
  }

  private var _isFinished: Bool = false
  override public private(set) var isFinished: Bool {
    get {
      return lockQueue.sync { () -> Bool in
        _isFinished
      }
    }
    set {
      willChangeValue(forKey: "isFinished")
      lockQueue.sync(flags: [.barrier]) {
        _isFinished = newValue
      }
      didChangeValue(forKey: "isFinished")
    }
  }

  init(block: @escaping (HttpOperation) -> URLSessionTask?) {
    self.block = block
    super.init()
  }

  override public func main() {
    let task = block(self)
    if let task = task {
      onUrlSessionTask?(task)
    }
    self.urlSessionTask = task
  }

  internal func finished() {
    isExecuting = false
    isFinished = true
  }

  override public func cancel() {
    urlSessionTask?.cancel()
    super.cancel()
  }
}
