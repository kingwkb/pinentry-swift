# pinentry-swift

![Build](https://github.com/kingwkb/pinentry-swift/workflows/Build%20and%20Release/badge.svg)
![Platform](https://img.shields.io/badge/Platform-macOS%2012.0+-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue?logo=swift)
![Touch ID](https://img.shields.io/badge/Touch%20ID-✓-green)
![Homebrew](https://img.shields.io/badge/Homebrew-✓-yellow?logo=homebrew)

A modern, native macOS pinentry program for GnuPG with Touch ID support and Keychain integration.

## Features

- **Native macOS UI** - Built with SwiftUI for a seamless macOS experience
- **Touch ID Integration** - Use biometrics to verify identity before retrieving saved passphrases
- **Keychain Storage** - Securely store passphrases in macOS Keychain
- **GPG Protocol Compliant** - Full support for the Assuan pinentry protocol

## Installation

### Via Homebrew

```bash
brew tap kingwkb/tap
brew install pinentry-swift
```

## Configuration

Configure GPG to use pinentry-swift by editing `~/.gnupg/gpg-agent.conf`:

```conf
pinentry-program /opt/homebrew/bin/pinentry-swift
```

Restart the GPG agent:
```bash
gpgconf --kill gpg-agent
```

## Usage

Once configured, pinentry-swift will automatically handle all GPG passphrase requests. 

### Touch ID & Keychain

When prompted for a passphrase:
1. Check "Save in Keychain (Touch ID)" to store the passphrase
2. On subsequent uses, authenticate with Touch ID to retrieve the saved passphrase
3. Passphrases are stored securely in macOS Keychain


## Requirements

- macOS 12.0 (Monterey) or later
- GnuPG 2.x

## Security

- **No network access** - All operations are local
- **Keychain protection** - Passphrases stored in macOS Keychain
- **Open source** - Fully auditable code