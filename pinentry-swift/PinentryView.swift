import SwiftUI

enum PinentryMode {
    case input
    case confirm
    case message
}

struct PinentryView: View {
    var mode: PinentryMode
    var title: String
    var desc: String
    var prompt: String
    var keyInfo: String?
    var okText: String
    var cancelText: String
    var isError: Bool
    var allowKeychain: Bool
    
    // New parameters for Repeat/Double entry
    var repeatPrompt: String?
    var repeatError: String
    
    var onCommitInput: ((String?, Bool) -> Void)?
    var onConfirm: ((Bool) -> Void)?
    var onMessageDismiss: (() -> Void)?
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var saveInKeychain = false
    @State private var localErrorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // 1. Icon
            Image(systemName: currentIconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .foregroundColor(currentIconColor)
                .padding(.top, 8)
            
            // 2. Description / Error Message
            ScrollView {
                Text(localErrorMessage ?? desc)
                    .multilineTextAlignment(.center)
                    .font((isError || localErrorMessage != nil) ? .headline : .callout)
                    .foregroundColor((isError || localErrorMessage != nil) ? .red : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }
            .frame(maxHeight: 120)
            
            // 3. Technical Key Info (Keygrip)
            if let keyInfo = keyInfo, !keyInfo.isEmpty, keyInfo != "default" {
                Text("Keygrip: \(keyInfo)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("Internal Key ID used by GPG Agent")
            }
            
            // 4. Input Fields
            if mode == .input {
                VStack(alignment: .leading, spacing: 6) {
                    // First Input
                    Text(prompt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    SecureField("", text: $password, onCommit: {
                        if repeatPrompt == nil {
                            submit()
                        }
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 260)
                    
                    // Second Input (if active)
                    if let repeatLabel = repeatPrompt {
                        Text(repeatLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        SecureField("", text: $confirmPassword, onCommit: submit)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(minWidth: 260)
                    }
                    
                    // Keychain toggle (Hidden in Repeat mode)
                    if allowKeychain && repeatPrompt == nil {
                        Toggle("Save in Keychain (Touch ID)", isOn: $saveInKeychain)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
            }
            
            // 5. Buttons
            HStack(spacing: 12) {
                if mode != .message {
                    Button(cancelText) {
                        handleCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                
                Button(okText) {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .input && password.isEmpty)
            }
            .padding(.bottom, 8)
        }
        .padding(20)
        .frame(width: 420)
    }
    
    // MARK: - Helpers
    
    var currentIconName: String {
        if isError || localErrorMessage != nil { return "exclamationmark.shield" }
        switch mode {
        case .input: return "lock.shield"
        case .confirm: return "questionmark.circle"
        case .message: return "bubble.left.and.bubble.right"
        }
    }
    
    var currentIconColor: Color {
        return (isError || localErrorMessage != nil) ? .red : .accentColor
    }
    
    func submit() {
        switch mode {
        case .input:
            // Local Validation for Double Entry
            if repeatPrompt != nil {
                if password != confirmPassword {
                    withAnimation {
                        localErrorMessage = repeatError
                    }
                    confirmPassword = ""
                    // Do not submit, stay on window
                    return
                }
            }
            onCommitInput?(password, saveInKeychain)
            
        case .confirm: onConfirm?(true)
        case .message: onMessageDismiss?()
        }
    }
    
    func handleCancel() {
        switch mode {
        case .input: onCommitInput?(nil, false)
        case .confirm: onConfirm?(false)
        case .message: onMessageDismiss?()
        }
    }
}
