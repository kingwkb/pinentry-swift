import LocalAuthentication

class BiometricsHelper {
    static func authenticate(reason: String) -> (Bool, Error?) {
        let context = LAContext()
        // The text on the fallback button if Biometrics fails
        context.localizedCancelTitle = "Enter Password"
        context.localizedFallbackTitle = ""
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return (false, error)
        }
        
        let sema = DispatchSemaphore(value: 0)
        var successResult = false
        var errorResult: Error?
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            successResult = success
            errorResult = error
            sema.signal()
        }
        
        // Wait for user interaction
        sema.wait()
        return (successResult, errorResult)
    }
}
