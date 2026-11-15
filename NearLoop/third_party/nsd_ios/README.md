# nsd_ios 3.0.0 Flutter SwiftPM packaging fix

Vendored from pub.dev nsd_ios 3.0.0, https://github.com/sebastianhaberey/nsd.
MIT license and all three Swift source files are preserved unchanged.
The manifest and sources are relocated under ios/nsd_ios, and the product is
named nsd-ios as Flutter 3.38 expects. The CocoaPods source glob follows the
moved sources. This is selected via NearLoop dependency_overrides. Remove the
override after verifying a compatible upstream package on a physical iPhone.
