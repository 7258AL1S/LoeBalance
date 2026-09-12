import Foundation
import Security

struct StoredCredential: Codable, Equatable, Sendable {
    let refreshToken: String
    let userID: Int64
}

protocol CredentialStoreProtocol: Sendable {
    func load() throws -> StoredCredential?
    func save(_ credential: StoredCredential) throws
    func delete() throws
}

struct KeychainCredentialStore: CredentialStoreProtocol, Sendable {
    private static let service = "cx.loe.LoeBalance"
    private static let account = "sub2api-refresh-token"

    func load() throws -> StoredCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppError.keychainStatus(status)
        }
        guard let data = result as? Data else {
            throw AppError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(StoredCredential.self, from: data)
        } catch {
            throw AppError.invalidResponse
        }
    }

    func save(_ credential: StoredCredential) throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credential)
        } catch {
            throw AppError.invalidResponse
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AppError.keychainStatus(updateStatus)
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppError.keychainStatus(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychainStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
