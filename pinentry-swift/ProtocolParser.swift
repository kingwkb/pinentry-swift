import Foundation
import Darwin // Required for ttyname

class ProtocolParser {
    
    // MARK: - State
    // These variables store the transient configuration sent by GPG
    private var description: String = "Please enter your passphrase"
    private var prompt: String = "Passphrase:"
    private var keyInfo: String = "default"
    private var errorText: String? = nil
    private var windowTitle: String = "GPG Pinentry"
    
    private var okText: String = "OK"
    private var cancelText: String = "Cancel"
    private var notOkText: String? = nil
    
    private var repeatPrompt: String? = nil
    private var repeatError: String = "Passphrases do not match"
    
    private var timeout: Int = 0
    private var allowExternalCache = false
    
    // User-friendly label for Keychain items (e.g., "User Name (KEYID)")
    private var generatedKeychainLabel: String? = nil
    
    // MARK: - Main Handler
    
    func handleCommand(_ line: String) -> String? {
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanLine.isEmpty || cleanLine.hasPrefix("#") { return nil }
        
        let parts = cleanLine.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first?.uppercased() else { return nil }
        
        let args = parts.count > 1 ? parts[1] : ""
        let decodedArgs = args.removingPercentEncoding ?? args
        
        switch cmd {
        // --- Core Actions ---
        case "GETPIN":  return performGetPin()
        case "CONFIRM": return performConfirm()
        case "MESSAGE": return performMessage(msg: decodedArgs)
        case "GETINFO": return performGetInfo(args: decodedArgs)
        case "BYE":     return "OK"
            
        // --- UI Configuration ---
        case "SETDESC":
            self.description = decodedArgs
            self.generatedKeychainLabel = parseLabel(from: decodedArgs)
            return "OK"
        case "SETPROMPT":
            self.prompt = decodedArgs
            return "OK"
        case "SETTITLE":
            self.windowTitle = decodedArgs
            return "OK"
        case "SETERROR":
            self.errorText = "Incorrect passphrase. Please try again."
            return "OK"
        case "SETOK":
            self.okText = decodedArgs.isEmpty ? "OK" : decodedArgs
            return "OK"
        case "SETCANCEL":
            self.cancelText = decodedArgs.isEmpty ? "Cancel" : decodedArgs
            return "OK"
        case "SETNOTOK":
            self.notOkText = decodedArgs
            return "OK"
        case "SETQUALITYBAR", "SETQUALITYBAR_TT":
            return "OK" // Ignore visual tweaks not supported by native UI
            
        // --- Logic Configuration ---
        case "SETKEYINFO":
            // Handle GPG prefixes like "n/ABCD..." or "s/ABCD..."
            let rawKey = decodedArgs.components(separatedBy: " ").first ?? "default"
            if let slashIndex = rawKey.firstIndex(of: "/") {
                self.keyInfo = String(rawKey[rawKey.index(after: slashIndex)...])
            } else {
                self.keyInfo = rawKey
            }
            return "OK"
        case "SETREPEAT":
            self.repeatPrompt = decodedArgs
            return "OK"
        case "SETREPEATERROR":
            self.repeatError = decodedArgs
            return "OK"
        case "SETTIMEOUT":
            self.timeout = Int(decodedArgs) ?? 0
            return "OK"
        case "OPTION":
            if decodedArgs.contains("allow-external-password-cache") {
                self.allowExternalCache = true
            }
            return "OK"
            
        default:
            // Returning OK for unknown commands prevents blocking the agent
            return "OK"
        }
    }
    
    // MARK: - Action Logic
    
    private func performGetInfo(args: String) -> String {
        let request = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let env = ProcessInfo.processInfo.environment
        
        switch request {
        case "pid", "":
            return "D \(ProcessInfo.processInfo.processIdentifier)\nOK"
            
        case "version":
            let info = Bundle.main.infoDictionary
            let short = info?["CFBundleShortVersionString"] as? String ?? "0.0.1"
            let build = info?["CFBundleVersion"] as? String ?? "1"
            return "D \(short) (\(build))\nOK"
            
        case "tty_name":
            if let tty = env["GPG_TTY"], !tty.isEmpty { return "D \(tty)\nOK" }
            if let ptr = ttyname(STDIN_FILENO) { return "D \(String(cString: ptr))\nOK" }
            return "D \nOK"
            
        case "ttyinfo":
            // Format: <tty> <term> <display>
            let tty = env["GPG_TTY"] ?? "-"
            let term = env["TERM"] ?? "-"
            let display = env["DISPLAY"] ?? "-"
            return "D \(tty) \(term) \(display)\nOK"
            
        case "flavor":
            return "D pinentry-swift\nOK"
            
        default:
            return "ERR 83886361 Not supported"
        }
    }
    
    private func performGetPin() -> String {
        // 1. Attempt silent authentication (Touch ID + Keychain)
        if repeatPrompt == nil, errorText == nil, allowExternalCache,
           let savedPass = KeychainHelper.load(account: keyInfo) {
            // Note: System prompts for biometrics if AccessControl is set on the item
            let (success, _) = BiometricsHelper.authenticate(reason: "Authenticate to access your GPG key")
            if success {
                return "D \(escape(savedPass))\nOK"
            }
        }
        
        // 2. Prepare UI
        let sema = DispatchSemaphore(value: 0)
        var result: String? = nil
        var shouldSave = false
        
        // Handle Timeout
        var timeoutItem: DispatchWorkItem?
        if timeout > 0 {
            timeoutItem = DispatchWorkItem {
                DispatchQueue.main.async { WindowManager.shared.forceClose() }
                sema.signal()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout), execute: timeoutItem!)
        }
        
        // 3. Show UI (Main Thread)
        DispatchQueue.main.async {
            WindowManager.shared.showInput(
                title: self.windowTitle,
                desc: self.errorText ?? self.description,
                prompt: self.prompt,
                keyInfo: self.keyInfo,
                okText: self.okText,
                cancelText: self.notOkText ?? self.cancelText,
                isError: self.errorText != nil,
                allowKeychain: self.allowExternalCache,
                repeatPrompt: self.repeatPrompt,
                repeatError: self.repeatError
            ) { password, save in
                timeoutItem?.cancel()
                result = password
                shouldSave = save
                sema.signal()
            }
        }
        
        // Wait for UI result
        sema.wait()
        
        // Reset transient state
        self.errorText = nil
        self.notOkText = nil
        self.repeatPrompt = nil
        self.timeout = 0
        
        guard let pass = result else {
            return "ERR 83886179 Operation cancelled"
        }
        
        // 4. Save and Return
        if shouldSave && allowExternalCache {
            KeychainHelper.save(pass, account: keyInfo, label: generatedKeychainLabel)
        }
        
        return "D \(escape(pass))\nOK"
    }
    
    private func performConfirm() -> String {
        let sema = DispatchSemaphore(value: 0)
        var confirmed = false
        
        DispatchQueue.main.async {
            WindowManager.shared.showConfirm(
                title: self.windowTitle,
                desc: self.description,
                okText: self.okText,
                cancelText: self.notOkText ?? self.cancelText
            ) { res in
                confirmed = res
                sema.signal()
            }
        }
        sema.wait()
        self.notOkText = nil
        return confirmed ? "OK" : "ERR 114 Operation cancelled"
    }
    
    private func performMessage(msg: String) -> String {
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            WindowManager.shared.showMessage(title: self.windowTitle, desc: msg, okText: self.okText) {
                sema.signal()
            }
        }
        sema.wait()
        return "OK"
    }
    
    // MARK: - Helpers
    
    // Assuan protocol requires percent-encoding for data lines
    private func escape(_ string: String) -> String {
        let clean = string.filter { !$0.isNewline }.precomposedStringWithCanonicalMapping
        return clean.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? clean
    }
    
    // Simple parser to extract "Name (KEYID)" for Keychain labeling
    private func parseLabel(from desc: String) -> String? {
        var name: String? = nil
        if let start = desc.firstIndex(of: "\""), let end = desc.lastIndex(of: "\""), start != end {
            name = String(desc[desc.index(after: start)..<end])
        }
        
        let pattern = "(?i)ID[:\\s]+(0x)?([A-F0-9]{8,40})"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)) {
            let nsRange = match.range(at: match.numberOfRanges > 2 ? 2 : 1)
            if let range = Range(nsRange, in: desc) {
                let id = String(desc[range]).uppercased()
                return name != nil ? "\(name!) (\(id))" : "GPG ID \(id)"
            }
        }
        return name
    }
}
