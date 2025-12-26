import Foundation

class ProtocolParser {
    // Protocol State Variables
    var description: String = "Please enter your passphrase"
    var prompt: String = "Passphrase:"
    var keyInfo: String = "default"
    var errorText: String? = nil
    var windowTitle: String = "GPG Pinentry"
    
    // Button Configuration
    var okText: String = "OK"
    var cancelText: String = "Cancel"
    var notOkText: String? = nil
    
    // Repeat / New Password Logic
    var repeatPrompt: String? = nil
    var repeatError: String = "Passphrases do not match"
    
    // Timeout logic
    var timeout: Int = 0
    
    // GnuPG 2.4 Security Options
    var allowExternalCache = false
    
    // Store parsed user label (Name <Email> (ID)) for Keychain
    var generatedKeychainLabel: String? = nil
    
    func handleCommand(_ line: String) -> String? {
        // Global cleanup: remove leading/trailing newlines and spaces
        // This ensures the command and arguments are clean
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanLine.isEmpty { return nil }
        
        let parts = cleanLine.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first else { return nil }
        let args = parts.count > 1 ? parts[1] : ""
        
        // Decode percent-encoded strings (e.g., %20 -> Space)
        let decodedArgs = args.removingPercentEncoding ?? args
        
        switch cmd {
        case "GETPIN": return performGetPin()
        case "CONFIRM": return performConfirm()
        case "MESSAGE": return performMessage(msg: decodedArgs)
            
        case "SETDESC":
            self.description = decodedArgs
            // Parse a user-friendly label immediately
            self.generatedKeychainLabel = parseUserAndKeyID(from: decodedArgs)
            return "OK"
            
        case "SETKEYINFO":
            // Remove prefix like "n/" or "s/" to match pinentry-mac behavior
            // e.g., "n/093FDB..." -> "093FDB..."
            let cleanArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawKey = cleanArgs.components(separatedBy: " ").first ?? "default"
            
            if let slashIndex = rawKey.firstIndex(of: "/") {
                self.keyInfo = String(rawKey[rawKey.index(after: slashIndex)...])
            } else {
                self.keyInfo = rawKey
            }
            return "OK"
            
        case "SETPROMPT": self.prompt = decodedArgs; return "OK"
        case "SETTITLE": self.windowTitle = decodedArgs; return "OK"
        case "SETERROR": self.errorText = "Incorrect passphrase. Please try again."; return "OK"
        case "SETOK": self.okText = decodedArgs.isEmpty ? "OK" : decodedArgs; return "OK"
        case "SETCANCEL": self.cancelText = decodedArgs.isEmpty ? "Cancel" : decodedArgs; return "OK"
        case "SETNOTOK": self.notOkText = decodedArgs; return "OK"
        case "SETREPEAT": self.repeatPrompt = decodedArgs; return "OK"
        case "SETREPEATERROR": self.repeatError = decodedArgs; return "OK"
        case "SETTIMEOUT": self.timeout = Int(args) ?? 0; return "OK"
        
        case "OPTION":
            if args.contains("allow-external-password-cache") {
                self.allowExternalCache = true
            }
            return "OK"
            
        case "GETINFO":
            if args == "pid" || args.isEmpty {
                return "D \(ProcessInfo.processInfo.processIdentifier)\nOK"
            }
            return "ERR 83886361 Not supported"
            
        case "SETQUALITYBAR": return "OK"
        case "SETQUALITYBAR_TT": return "OK"
        case "BYE": return "OK"
        default: return "OK"
        }
    }
    
    // MARK: - Label Parsing
    
    // Target format: "First Last <email> (KEYID)"
    private func parseUserAndKeyID(from desc: String) -> String? {
        var name: String? = nil
        
        // 1. Extract name from quotes: "Name <Email>"
        if let start = desc.firstIndex(of: "\""),
           let end = desc.lastIndex(of: "\""), start != end {
            name = String(desc[desc.index(after: start)..<end])
        }
        
        // 2. Extract Key ID
        // Matches ID followed by hex string (8-40 chars), ignoring case and optional "0x"
        var keyID: String? = nil
        let pattern = "(?i)ID[:\\s]+(0x)?([A-F0-9]{8,40})"
        
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)) {
            // range(at: 2) corresponds to the raw hex ID group
            let captureIndex = match.numberOfRanges > 2 ? 2 : 1
            if let range = Range(match.range(at: captureIndex), in: desc) {
                keyID = String(desc[range])
            }
        }
        
        // 3. Assemble
        if let n = name, let k = keyID {
            return "\(n) (\(k.uppercased()))"
        } else if let n = name {
            return n
        } else if let k = keyID {
            return "GPG ID \(k.uppercased())"
        }
        
        return nil
    }
    
    // MARK: - Logic Handlers
    
    private func performGetPin() -> String {
        // Try reading from Keychain using the cleaned keyInfo (no prefix)
        if repeatPrompt == nil, errorText == nil, allowExternalCache, let savedPass = KeychainHelper.load(account: keyInfo) {
            let (success, _) = BiometricsHelper.authenticate(reason: self.windowTitle)
            if success {
                let escapedSaved = savedPass.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? savedPass
                return "D \(escapedSaved)\nOK"
            }
        }
        
        // UI Interaction
        let sema = DispatchSemaphore(value: 0)
        var result: String? = nil
        var shouldSave = false
        
        var timeoutWorkItem: DispatchWorkItem?
        if timeout > 0 {
            timeoutWorkItem = DispatchWorkItem {
                DispatchQueue.main.async { WindowManager.shared.forceClose() }
                sema.signal()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout), execute: timeoutWorkItem!)
        }
        
        let cancelLabel = notOkText ?? cancelText
        
        DispatchQueue.main.async {
            WindowManager.shared.showInput(
                title: self.windowTitle,
                desc: self.errorText ?? self.description,
                prompt: self.prompt,
                keyInfo: self.keyInfo,
                okText: self.okText,
                cancelText: cancelLabel,
                isError: self.errorText != nil,
                allowKeychain: self.allowExternalCache,
                repeatPrompt: self.repeatPrompt,
                repeatError: self.repeatError
            ) { password, save in
                timeoutWorkItem?.cancel()
                result = password
                shouldSave = save
                sema.signal()
            }
        }
        
        sema.wait()
        
        self.errorText = nil
        self.notOkText = nil
        self.repeatPrompt = nil
        self.timeout = 0
        
        guard let pass = result else {
            return "ERR 83886179 Operation cancelled"
        }
        
        // Save to Keychain if requested, using the parsed label
        if shouldSave && allowExternalCache {
            KeychainHelper.save(pass, account: keyInfo, label: self.generatedKeychainLabel)
        }
        
        // 1. Remove newlines (from paste).
        // 2. Normalize Unicode (NFC).
        // 3. Percent-encode special chars (required by Assuan protocol).
        let cleanPass = pass.filter { !$0.isNewline }.precomposedStringWithCanonicalMapping
        let escapedPass = cleanPass.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? cleanPass
        
        return "D \(escapedPass)\nOK"
    }
    
    private func performConfirm() -> String {
        let sema = DispatchSemaphore(value: 0)
        var confirmed = false
        let cancelLabel = notOkText ?? cancelText
        DispatchQueue.main.async {
            WindowManager.shared.showConfirm(title: self.windowTitle, desc: self.description, okText: self.okText, cancelText: cancelLabel) { result in
                confirmed = result
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
            WindowManager.shared.showMessage(title: self.windowTitle, desc: msg, okText: self.okText) { sema.signal() }
        }
        sema.wait()
        return "OK"
    }
}
