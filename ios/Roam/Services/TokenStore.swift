import Foundation
import Security

struct StoredAuthSession: Codable, Equatable, Sendable {
    let refreshToken: String
    let userID: String
    let user: AuthUser?
}

enum TokenStoreError: LocalizedError, Equatable, Sendable {
    case invalidData
    case readFailed(OSStatus)
    case saveFailed(OSStatus)
    case clearFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData: "Roam could not read its saved sign-in."
        case let .readFailed(status): "Roam could not read its saved sign-in (Keychain status " + String(status) + ")."
        case let .saveFailed(status): "Roam could not save your sign-in (Keychain status " + String(status) + ")."
        case let .clearFailed(status): "Roam could not clear your sign-in (Keychain status " + String(status) + ")."
        }
    }
}

protocol TokenStoreBackend: Sendable {
    func save(data: Data, service: String, account: String) throws
    func load(service: String, account: String) throws -> Data?
    func clear(service: String, account: String) throws
}

final class TokenStore: @unchecked Sendable {
    typealias StoredSession = StoredAuthSession

    private let service: String
    private let account = "auth-session"
    private let backend: any TokenStoreBackend

    init(
        service: String = "com.akhilkonduru.roam.auth",
        backend: any TokenStoreBackend = KeychainTokenStoreBackend()
    ) {
        self.service = service
        self.backend = backend
    }

    func save(refreshToken: String, user: AuthUser) throws {
        guard !refreshToken.isEmpty, !user.id.isEmpty else { throw TokenStoreError.invalidData }
        let session = StoredAuthSession(refreshToken: refreshToken, userID: user.id, user: user)
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw TokenStoreError.invalidData
        }
        try backend.save(data: data, service: service, account: account)
    }

    func load() throws -> StoredAuthSession? {
        guard let data = try backend.load(service: service, account: account) else { return nil }
        do {
            return try JSONDecoder().decode(StoredAuthSession.self, from: data)
        } catch {
            throw TokenStoreError.invalidData
        }
    }

    func clear() throws {
        try backend.clear(service: service, account: account)
    }
}

private struct KeychainTokenStoreBackend: TokenStoreBackend {
    func save(data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            // The app target is iOS. The host-only standalone checks cannot
            // access macOS Keychain in this sandbox, so they inject a backend.
            #if !os(macOS)
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            #endif
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw TokenStoreError.saveFailed(addStatus) }
        default:
            throw TokenStoreError.saveFailed(updateStatus)
        }
    }

    func load(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw TokenStoreError.invalidData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.readFailed(status)
        }
    }

    func clear(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw TokenStoreError.clearFailed(status)
        }
    }
}
