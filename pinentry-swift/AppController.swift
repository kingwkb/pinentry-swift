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
        
#if DEBUG
        let fileManager = FileManager.default
        let logsDirectory = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/gpg_logs")
        try? fileManager.createDirectory(atPath: logsDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let timestamp = formatter.string(from: Date())
        let pid = ProcessInfo.processInfo.processIdentifier
        
        let filename = "gpg_session_\(timestamp)_pid\(pid).txt"
        
        let logPath = (logsDirectory as NSString).appendingPathComponent(filename)
        
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)

#endif
        
        
        while let line = readLine() {
#if DEBUG
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                if let data = "\(line)\n".data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
#endif
            
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
