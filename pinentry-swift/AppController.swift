import Cocoa

class AppController: NSObject, NSApplicationDelegate {
    let parser = ProtocolParser()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run the GPG Assuan protocol listener on a background thread
        // to keep the main thread free for UI rendering.
        DispatchQueue.global(qos: .userInitiated).async {
            self.startGPGListener()
        }
    }
    
    func startGPGListener() {
        // GPG Handshake
        print("OK Pleased to meet you")
        fflush(stdout)
        
        while let line = readLine() {
            if let response = parser.handleCommand(line) {
                print(response)
                fflush(stdout)
            }
            
            // BYE is the standard command to terminate the agent connection
            if line.hasPrefix("BYE") {
                exit(0)
            }
        }
    }
}
