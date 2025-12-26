import Cocoa
import Foundation

// 1. Maintain a strong reference to the delegate to prevent ARC deallocation
let delegate = AppController()

// 2. Initialize Application
let app = NSApplication.shared
// Accessory policy: No Dock icon, allows UI
app.setActivationPolicy(.accessory)

// 3. Setup System Menu (Crucial for Copy/Paste support in SecureField)
AppMenu.setup()

// 4. Set Delegate
app.delegate = delegate

// 5. Run Main Loop
app.run()
