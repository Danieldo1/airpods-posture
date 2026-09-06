# ColorSelector source resolution

Both AirPosture build paths use this local package, resolved to upstream [ColorSelector v2.3.1](https://github.com/jaywcjlove/ColorSelector/tree/d73937d4c68894170001f331ce991ccaeffa73b5), commit `d73937d4c68894170001f331ce991ccaeffa73b5`. `UPSTREAM.json` records upstream and included SHA-256 hashes for every library source and unchanged package/license metadata.

The sole compatibility patch wraps nine trailing preview-only blocks in `#if canImport(PreviewsMacros)` / `#endif`. Apple Command Line Tools do not supply that preview macro plugin. Runtime library code and the upstream Swift 6.1 manifest remain unchanged. There are no resource bundles or further dependencies. The MIT license is preserved in LICENSE.

SwiftPM local package references do not produce Package.resolved pins; this immutable source/provenance manifest is shared by Package.swift and the Xcode project. To update, resolve an explicit upstream commit and regenerate/verify every hash and preview-only diff.
