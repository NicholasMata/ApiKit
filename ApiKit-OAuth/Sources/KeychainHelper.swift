//
//  KeychainHelper.swift
//
//
//  Created by Nicholas Mata on 6/14/22.
//

import Foundation

public final class KeychainHelper {
   public static let standard = KeychainHelper()
  private init() {}

  public func save(_ data: Data, forService service: String, account: String) -> Bool {
    let query = [
      kSecValueData: data,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecClass: kSecClassGenericPassword,
    ] as CFDictionary

    // Add data in query to keychain
    let status = SecItemAdd(query, nil)

    if status == errSecDuplicateItem {
      // Item already exist, thus update it.
      let query = [
        kSecAttrService: service,
        kSecAttrAccount: account,
        kSecClass: kSecClassGenericPassword,
      ] as CFDictionary

      let attributesToUpdate = [kSecValueData: data] as CFDictionary

      // Update existing item
      let status = SecItemUpdate(query, attributesToUpdate)
    }
    return status == errSecSuccess
  }

  public func read(service: String, account: String) -> Data? {
    let query = [
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecClass: kSecClassGenericPassword,
      kSecReturnData: true,
    ] as CFDictionary

    var result: AnyObject?
    SecItemCopyMatching(query, &result)

    return (result as? Data)
  }

  public func delete(service: String, account: String) -> Bool {
    let query = [
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecClass: kSecClassGenericPassword,
    ] as CFDictionary

    // Delete item from keychain
    let status = SecItemDelete(query)
    return status == errSecSuccess
  }
}

private extension KeychainHelper {
  func save(_ data: Data?, service: String, account: String) {
    guard let data = data else {
      _ = delete(service: service, account: account)
      return
    }
    save(data, service: service, account: account)
  }
}

private extension KeychainHelper {
  func save<T>(_ item: T, service: String, account: String) where T: Codable {
    do {
      // Encode as JSON data and save in keychain
      let data = try JSONEncoder().encode(item)
      save(data, service: service, account: account)

    } catch {
      assertionFailure("Fail to encode item for keychain: \(error)")
    }
  }

  func read<T>(service: String, account: String, type: T.Type) -> T? where T: Codable {
    // Read item data from keychain
    guard let data = read(service: service, account: account) else {
      return nil
    }

    // Decode JSON data to object
    do {
      let item = try JSONDecoder().decode(type, from: data)
      return item
    } catch {
      assertionFailure("Fail to decode item for keychain: \(error)")
      return nil
    }
  }
}
