//
//  GoogleAuthInterceptor.swift
//
//
//  Created by Nicholas Mata on 6/8/22.
//

import ApiKit
import Foundation

open class DefaultGoogleAuthInterceptor: OAuthInterceptor {
  public init(onFailedToRenew: ((Error?) -> Void)? = nil) {
    super.init(provider: DefaultGoogleAuthProvider(), onFailedToRenew: onFailedToRenew)
  }
}
