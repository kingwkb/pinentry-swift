import Foundation
import Darwin // Required for ttyname and STDIN_FILENO

class ProtocolParser {
    // MARK: - Protocol State Variables
    var description: String = "Please enter your passphrase"
    var prompt: String = "Passphrase:"
    var keyInfo: String = "default"
    var errorText: String? = nil
    var windowTitle: String = "GPG Pinentry"
    
    // MARK: - UI Configuration
    var okText: String = "OK"
    var cancelText: String = "Cancel"
    var notOkText: String? = nil
    
    // MARK: - Repeat / Validation Logic
    var repeatPrompt: String? = nil
    var repeatError: String = "Passphrases do not match"
    
    // MARK: - Timeout & Security Options
    var timeout: Int = 0
    var allowExternalCache = false
    
    // Store parsed user label (Name <Email> (ID)) for Keychain
    var generatedKeychainLabel: String? = nil
    
    // MARK: - Command Handling
    
    func handleCommand(_ line: String) -> String? {
        // Clean up input: remove leading/trailing whitespace
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanLine.isEmpty || cleanLine.hasPrefix("#") { return nil }
        
        let parts = cleanLine.split(separator: " ", maxSplits: 1).map(String.init)
        guard let cmd = parts.first else { return nil }
        let args = parts.count > 1 ? parts[1] : ""
        
        // Decode percent-encoded strings (e.g., %20 -> Space)
        // GPG sends arguments properly escaped.
        let decodedArgs = args.removingPercentEncoding ?? args
        
        switch cmd.uppercased() {
        case "GETPIN":
            return performGetPin()
            
        case "CONFIRM":
            return performConfirm()
            
        case "MESSAGE":
            return performMessage(msg: decodedArgs)
            
        case "SETDESC":
            self.description = decodedArgs
            self.generatedKeychainLabel = parseUserAndKeyID(from: decodedArgs)
            return "OK"
            
        case "SETKEYINFO":
            // Handle prefix like "n/" or "s/" used by GPG (e.g., "n/093FDB...")
            let cleanArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawKey = cleanArgs.components(separatedBy: " ").first ?? "default"
            
            if let slashIndex = rawKey.firstIndex(of: "/") {
                self.keyInfo = String(rawKey[rawKey.index(after: slashIndex)...])
            } else {
                self.keyInfo = rawKey
            }
            return "OK"
            
        case "SETPROMPT":
            self.prompt = decodedArgs
            return "OK"
            
        case "SETTITLE":
            self.windowTitle = decodedArgs
            return "OK"
            
        case "SETERROR":
            // GPG sets this if the previous attempt failed
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
            
        case "SETREPEAT":
            self.repeatPrompt = decodedArgs
            return "OK"
            
        case "SETREPEATERROR":
            self.repeatError = decodedArgs
            return "OK"
            
        case "SETTIMEOUT":
            self.timeout = Int(args) ?? 0
            return "OK"
            
        case "OPTION":
            if args.contains("allow-external-password-cache") {
                self.allowExternalCache = true
            }
            return "OK"
            
        case "GETINFO":
            return performGetInfo(args: args)
            
        // Ignore visual tweaks not supported by standard macOS UI
        case "SETQUALITYBAR", "SETQUALITYBAR_TT":
            return "OK"
            
        case "BYE":
            return "OK"
            
        default:
            // Return OK for unknown commands to prevent blocking the agent,
            // or return standard error if strict compliance is required.
            return "OK"
        }
    }
    
    // MARK: - GETINFO Handler
    
    private func performGetInfo(args: String) -> String {
        let request = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let env = ProcessInfo.processInfo.environment
        
        switch request {
        case "pid", "":
            // Return the Process ID of this pinentry instance
            return "D \(ProcessInfo.processInfo.processIdentifier)\nOK"
            
        case "version":
            // Fetch version from Info.plist (CFBundleShortVersionString)
            let info = Bundle.main.infoDictionary
            let shortVer = info?["CFBundleShortVersionString"] as? String ?? "1.0"
            let buildVer = info?["CFBundleVersion"] as? String ?? "1"
            return "D \(shortVer) (\(buildVer))\nOK"
            
        case "tty_name":
            // Priority 1: GPG_TTY environment variable
            if let gpgTTY = env["GPG_TTY"], !gpgTTY.isEmpty {
                return "D \(gpgTTY)\nOK"
            }
            // Priority 2: Standard C API check
            if let ttyPtr = ttyname(STDIN_FILENO) {
                return "D \(String(cString: ttyPtr))\nOK"
            }
            // Priority 3: Return empty (No TTY associated)
            return "D \nOK"
            
        case "ttyinfo":
            // Format: <tty_name> <term_type> <display>
            let tty = env["GPG_TTY"] ?? "-"
            let term = env["TERM"] ?? "-"
            let display = env["DISPLAY"] ?? "-"
            return "D \(tty) \(term) \(display)\nOK"
            
        case "flavor":
            // Identify as Swift implementation
            return "D pinentry-swift\nOK"
            
        case "socket_name", "display":
            // Return empty data for unsupported but common queries
            return "D \nOK"
            
        default:
            // ERR 83886361 = "Not supported" (Source 5 + Code 281)
            return "ERR 83886361 Not supported"
        }
    }
    
    // MARK: - Label Parsing
    
    // Parses "First Last <email> (KEYID)" into "First Last (KEYID)" for Keychain labeling
    private func parseUserAndKeyID(from desc: String) -> String? {
        var name: String? = nil
        
        // 1. Extract name from quotes: "Name <Email>"
        if let start = desc.firstIndex(of: "\""),
           let end = desc.lastIndex(of: "\""), start != end {
            name = String(desc[desc.index(after: start)..<end])
        }
        
        // 2. Extract Key ID (Hex string)
        var keyID: String? = nil
        let pattern = "(?i)ID[:\\s]+(0x)?([A-F0-9]{8,40})"
        
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)) {
            // Group 2 contains the raw hex ID
            let captureIndex = match.numberOfRanges > 2 ? 2 : 1
            if let range = Range(match.range(at: captureIndex), in: desc) {
                keyID = String(desc[range])
            }
        }
        
        // 3. Assemble readable label
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
        // 1. Try silent authentication via Touch ID + Keychain
        // Ensure repeatPrompt is nil (don't autocomplete during password change)
        if repeatPrompt == nil, errorText == nil, allowExternalCache, let savedPass = KeychainHelper.load(account: keyInfo) {
            // Note: The actual biometrics prompt often happens inside KeychainHelper
            // depending on SecAccessControl flags.
            let (success, _) = BiometricsHelper.authenticate(reason: self.windowTitle)
            if success {
                let escapedSaved = savedPass.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? savedPass
                return "D \(escapedSaved)\nOK"
            }
        }
        
        // 2. User Interaction (UI)
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
        
        // Reset transient state
        self.errorText = nil
        self.notOkText = nil
        self.repeatPrompt = nil
        self.timeout = 0
        
        guard let pass = result else {
            // ERR 83886179 = "Operation cancelled"
            return "ERR 83886179 Operation cancelled"
        }
        
        // 3. Save to Keychain if requested
        if shouldSave && allowExternalCache {
            KeychainHelper.save(pass, account: keyInfo, label: self.generatedKeychainLabel)
        }
        
        // 4. Format Output
        // Remove newlines, normalize Unicode, and percent-encode
        let cleanPass = pass.filter { !$0.isNewline }.precomposedStringWithCanonicalMapping
        let escapedPass = cleanPass.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? cleanPass
        
        return "D \(escapedPass)\nOK"
    }
    
    private func performConfirm() -> String {
        let sema = DispatchSemaphore(value: 0)
        var confirmed = false
        let cancelLabel = notOkText ?? cancelText
        
        DispatchQueue.main.async {
            WindowManager.shared.showConfirm(
                title: self.windowTitle,
                desc: self.description,
                okText: self.okText,
                cancelText: cancelLabel
            ) { result in
                confirmed = result
                sema.signal()
            }
        }
        sema.wait()
        
        self.notOkText = nil
        // ERR 114 = "Operation cancelled" (Legacy code)
        return confirmed ? "OK" : "ERR 114 Operation cancelled"
    }
    
    private func performMessage(msg: String) -> String {
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            WindowManager.shared.showMessage(
                title: self.windowTitle,
                desc: msg,
                okText: self.okText
            ) {
                sema.signal()
            }
        }
        sema.wait()
        return "OK"
    }
}
