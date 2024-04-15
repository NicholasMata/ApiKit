//
//  OIDCTokenManager.swift
//
//
//  Created by Nicholas Mata on 4/14/24.
//

import Foundation

private let expiresInKey = "expires_in"
private let retrievedOnKey = "retrieved_on"

public class OIDCTokenManager: TokenManager {
    private var account: String
    public var accessToken: Token? = nil {
      didSet {
            OIDCTokenManager.store(token: refreshToken, with: "refresh_token", for: account)
      }
    }

    public var refreshToken: Token? = nil {
        didSet {
            OIDCTokenManager.store(token: refreshToken, with: "refresh_token", for: account)
        }
    }

    public var idToken: String? = nil {
        didSet {
            OIDCTokenManager.store(idToken: idToken, for: account)
        }
    }

    public var hasValidToken: Bool {
        return refreshToken?.isValid() ?? false
    }

    private var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    public init(account: String) {
        self.account = account
      if let idTokenData = KeychainHelper.standard.read(service: "id_token", account: account) {
            idToken = String(data: idTokenData, encoding: .utf8)
        }
        refreshToken = OIDCTokenManager.token(with: "refresh_token", for: account)
    }

    public func decode(from response: Data) {
        guard let response = try? decoder.decode(OIDCTokenResponse.self, from: response) else {
            return
        }
      accessToken = Token(token: response.accessToken, expiresIn: response.expiresIn, retrievedOn: Date())
        if let refreshToken = response.refreshToken {
            let refreshTokenExpiresIn = response.refreshTokenExpiresIn ?? Int.max
            DispatchQueue.main.async {
                self.refreshToken = Token(token: refreshToken, expiresIn: refreshTokenExpiresIn, retrievedOn: Date())
            }
        }
        DispatchQueue.main.async {
            self.idToken = response.idToken
        }
    }

    public func clear() {
        DispatchQueue.main.async {
            self.refreshToken = nil
            self.idToken = nil
            self.accessToken = nil
        }
    }

    private static func store(idToken: String?, for account: String) {
        guard let idToken = idToken else {
            return
        }
        if let idTokenData = idToken.data(using: .utf8) {
          _ = KeychainHelper.standard.save(idTokenData, forService: "id_token", account: account)
        }
    }

    private static func store(token: Token?, with tokenName: String, for account: String) {
        guard let token = token else {
          if KeychainHelper.standard.delete(service: tokenName, account: account) {
                UserDefaults.standard.removeObject(forKey: "\(account):\(tokenName):\(expiresInKey)")
                UserDefaults.standard.removeObject(forKey: "\(account):\(tokenName):\(retrievedOnKey)")
            }
            return
        }
        guard let tokenData = token.token.data(using: .utf8) else {
            return
        }
      let saved = KeychainHelper.standard.save(tokenData, forService: tokenName, account: account)
        if saved {
            UserDefaults.standard.set(token.expiresIn, forKey: "\(account):\(tokenName):\(expiresInKey)")
            UserDefaults.standard.set(token.retrievedOn.timeIntervalSince1970, forKey: "\(account):\(tokenName):\(retrievedOnKey)")
        }
    }

    private static func token(with tokenName: String, for account: String) -> Token? {
        let expiresIn = UserDefaults.standard.integer(forKey: "\(account):\(tokenName):\(expiresInKey)")
        let retrievedOn = UserDefaults.standard.double(forKey: "\(account):\(tokenName):\(retrievedOnKey)")

      if let tokenData = KeychainHelper.standard.read(service: tokenName, account: account),
           let tokenValue = String(data: tokenData, encoding: .utf8),
           expiresIn > 0,
           retrievedOn > 0
        {
            let retrievedOn = Date(timeIntervalSince1970: retrievedOn)
            return Token(token: tokenValue, expiresIn: expiresIn, retrievedOn: retrievedOn)
        }
        return nil
    }
}
