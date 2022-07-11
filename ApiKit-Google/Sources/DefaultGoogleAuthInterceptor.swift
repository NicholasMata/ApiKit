//
//  GoogleAuthInterceptor.swift
//
//
//  Created by Nicholas Mata on 6/8/22.
//

import ApiKit
import Foundation

public class DefaultGoogleAuthInterceptor: OAuthInterceptor {
  public init(onNotSignedIn: @escaping (Error?) -> Void) {
    super.init(provider: DefaultGoogleAuthProvider(), onNotSignedIn: onNotSignedIn)
  }
}
