// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Clarity",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "ClarityCore", targets: ["ClarityCore"]),
    .library(name: "ClarityBreaks", targets: ["ClarityBreaks"]),
    .executable(name: "Clarity", targets: ["ClarityDiagnostics"]),
  ],
  targets: [
    .target(name: "ClarityBreaks"),
    .target(
      name: "ClarityCore",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ColorSync"),
        .linkedFramework("CoreGraphics"),
      ]
    ),
    .executableTarget(
      name: "ClarityDiagnostics",
      dependencies: ["ClarityCore", "ClarityBreaks"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ApplicationServices"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("CoreLocation"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("CoreMediaIO"),
        .linkedFramework("EventKit"),
        .linkedFramework("GameController"),
        .linkedFramework("IOKit"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "ClarityCoreTests",
      dependencies: ["ClarityCore"]
    ),
    .testTarget(
      name: "ClarityBreaksTests",
      dependencies: ["ClarityBreaks"]
    ),
    .testTarget(
      name: "ClarityDiagnosticsTests",
      dependencies: ["ClarityDiagnostics"]
    ),
  ]
)
