import Foundation
import Security

/// 首次启动时把 App 和本机安装的 ipatool 加入该凭证的信任列表。
/// 之后只读取现有设置，不再重复修改或弹窗。
enum KeychainAccess {
    static let serviceName = "ipatool-auth.service"

    private static let lock = NSLock()
    private static var didAttempt = false

    static func allowIpatoolWithoutPrompt() {
        lock.lock()
        defer { lock.unlock() }
        guard !didAttempt else { return }
        didAttempt = true
        _ = grantAccessIfNeeded()
    }

    /// 登录会重写钥匙串项，允许再授权一次。
    static func noteCredentialsChanged() {
        lock.lock()
        didAttempt = false
        lock.unlock()
    }

    @discardableResult
    private static func grantAccessIfNeeded() -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: "account",
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnRef: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result else { return false }

        let item = unsafeBitCast(result, to: SecKeychainItem.self)
        let trusted = trustedApplications()
        guard !trusted.isEmpty else { return false }
        return applyTrustedApplications(to: item, trusted: trusted)
    }

    private static func trustedApplications() -> [SecTrustedApplication] {
        var apps: [SecTrustedApplication] = []
        var host: SecTrustedApplication?
        if SecTrustedApplicationCreateFromPath(nil, &host) == errSecSuccess, let host {
            apps.append(host)
        }
        if let path = try? IPAToolService.resolveBinary().path {
            var helper: SecTrustedApplication?
            if SecTrustedApplicationCreateFromPath(path, &helper) == errSecSuccess, let helper {
                apps.append(helper)
            }
        }
        return apps
    }

    private static func applyTrustedApplications(
        to item: SecKeychainItem,
        trusted: [SecTrustedApplication]
    ) -> Bool {
        var access: SecAccess?
        guard SecKeychainItemCopyAccess(item, &access) == errSecSuccess,
              let access,
              let aclList = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt) else {
            return false
        }

        var entries: [(SecACL, [SecTrustedApplication], CFString, SecKeychainPromptSelector, Bool)] = []
        var trustedIDs = Set<Data>()
        for index in 0..<CFArrayGetCount(aclList) {
            let acl = unsafeBitCast(CFArrayGetValueAtIndex(aclList, index), to: SecACL.self)
            var apps: CFArray?
            var description: CFString?
            var prompt = SecKeychainPromptSelector()
            guard SecACLCopyContents(acl, &apps, &description, &prompt) == errSecSuccess else {
                continue
            }
            let current = apps.map(trustedApplications(from:)) ?? []
            current.compactMap(identityData).forEach { trustedIDs.insert($0) }
            entries.append((acl, current, description ?? (serviceName as CFString), prompt, apps == nil))
        }

        let unrestricted = entries.filter(\.4)
        if !unrestricted.isEmpty {
            for (acl, _, description, prompt, _) in unrestricted {
                guard SecACLSetContents(acl, trusted as CFArray, description, prompt) == errSecSuccess else {
                    return false
                }
            }
            return SecKeychainItemSetAccess(item, access) == errSecSuccess
        }

        let missing = trusted.filter { app in
            guard let id = identityData(app) else { return true }
            return !trustedIDs.contains(id)
        }
        guard !missing.isEmpty else { return true }
        guard let (acl, current, description, prompt, _) = entries.first else { return false }
        guard SecACLSetContents(acl, (current + missing) as CFArray, description, prompt) == errSecSuccess else {
            return false
        }
        return SecKeychainItemSetAccess(item, access) == errSecSuccess
    }

    private static func trustedApplications(from array: CFArray) -> [SecTrustedApplication] {
        (0..<CFArrayGetCount(array)).map { index in
            unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: SecTrustedApplication.self)
        }
    }

    private static func identityData(_ app: SecTrustedApplication) -> Data? {
        var data: CFData?
        guard SecTrustedApplicationCopyData(app, &data) == errSecSuccess else { return nil }
        return data as Data?
    }
}
