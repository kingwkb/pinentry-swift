import Security
import Foundation

class KeychainHelper {
    // Service Name: Visible in Keychain Access.
    // Changing this invalidates previous entries signed by a different binary.
    static let service = "GnuPG"
    
    static func save(_ pass: String, account: String, label: String? = nil) {
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty else { return }
        
        guard let data = pass.data(using: .utf8) else { return }
        
        let finalLabel = label ?? "GnuPG"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cleanAccount,
            kSecAttrLabel as String: finalLabel,
            kSecValueData as String: data
        ]
        
        // Delete existing item to update it
        SecItemDelete(query as CFDictionary)
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
