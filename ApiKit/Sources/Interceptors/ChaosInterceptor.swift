//
//  ChaosInterceptor.swift
//
//
//  Created by Nicholas Mata on 6/10/22.
//

import Foundation

/// Used to cause chaos making some request randomly fail.
/// Helper because reminds the developer to handle fail cases properly.
open class ChaosInterceptor: ApiInterceptor {
  var probability: Int

  /// Initial ChaosInterceptor
  /// - Parameter probability: The probability of Chaos from 0% - 100%. Where 100 means Chaos is guaranteed. Default is 20%.
  init(probability: Int = 20) {
    self.probability = min(max(probability, 0), 100)
  }

  enum ChaosError: Error {
    case monkeyingAround
  }

  public func api(_: Api,
                  willSendRequest _: URLRequest,
                  withId _: UUID,
                  completion: HttpDataCompletion) -> Bool
  {
    let failureChance = Int.random(in: 1 ... 100)
    if failureChance <= probability {
      DispatchQueue.global(qos: .background)
        .asyncAfter(deadline: .now() + Double.random(in: 0 ... 2)) {
          completion?(.failure(ChaosError.monkeyingAround))
        }
      return true
    }
    return false
  }
}

extension ChaosInterceptor.ChaosError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .monkeyingAround:
      return "🐒 was monkeying around."
    }
  }
}
