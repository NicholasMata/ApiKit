//
//  ConnectivityInterceptor.swift
//
//
//  Created by Nicholas Mata on 7/11/22.
//

import Foundation
import Network

/// Errors that ConnectivityInterceptor throws.
enum ConnectivityError: Error {
  /// There is no internet connectivity.
  case noConnectivity
}

/// Used to intercept request when no internet connectivity and instantly return an error without even making the request.
/// Uses NWPathMonitor behind the scenes.
public class ConnectivityInterceptor: ApiInterceptor {
  let monitor: NWPathMonitor
  public static var defaultQueue = DispatchQueue(label: "ApiConnectivity")
  
  public init(dispatchQueue: DispatchQueue? = nil) {
    monitor = NWPathMonitor()
    monitor.start(queue: dispatchQueue ?? ConnectivityInterceptor.defaultQueue)
  }
  
  public init(requireInterfaceType: NWInterface.InterfaceType, dispatchQueue: DispatchQueue? = nil) {
    monitor = NWPathMonitor(requiredInterfaceType: requireInterfaceType)
    monitor.start(queue: dispatchQueue ?? ConnectivityInterceptor.defaultQueue)
  }
  
  public func api(_ api: Api, willSendRequest request: URLRequest, withId identifier: UUID, completion: HttpDataCompletion) -> Bool {
    guard monitor.currentPath.status == .satisfied else {
      completion?(.failure(ConnectivityError.noConnectivity))
      return true
    }
    return false
  }
}
