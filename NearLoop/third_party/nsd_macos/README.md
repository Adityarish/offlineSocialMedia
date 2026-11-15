# nsd_macos 3.0.0: Flutter 3.38 SwiftPM packaging fix

Vendored from the pub.dev `nsd_macos` 3.0.0 archive (upstream:
https://github.com/sebastianhaberey/nsd). The MIT license is preserved in LICENSE.
The three Swift source files are unchanged from the published package.

The published manifest is at the package root and exports `nsd_macos`.
Flutter 3.38 looks for `macos/nsd_macos/Package.swift` and links the product
`nsd-macos`, so it otherwise omits this plugin from its generated Swift package.

This copy moves the sources inside the expected Swift package, exports the
expected product while retaining the `nsd_macos` module and upstream minimum
OS version. NearLoop itself targets macOS 12.0. The CocoaPods source glob follows the moved sources.
NearLoop selects this copy through its pubspec dependency override; do not
patch the pub cache or generated registrant to maintain this fix.

Remove the override when upgrading to an upstream release with compatible
Flutter SwiftPM packaging, after verifying a native macOS build and discovery.
