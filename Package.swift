// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "ApiKit",
  platforms: [.iOS(.v12), .macOS(.v12)],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .library(
      name: "ApiKit",
      targets: ["ApiKit"]
    ),
    .library(
      name: "ApiKit-Google",
      targets: ["ApiKit-Google"]
    ),
    .library(
      name: "ApiKit-OAuth",
      targets: ["ApiKit-OAuth"]
    ),
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "6.0.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages this package depends on.
    .target(
      name: "ApiKit",
      dependencies: [],
      path: "ApiKit/Sources"
    ),
    .testTarget(
      name: "ApiKitTests",
      dependencies: ["ApiKit"],
      path: "ApiKit/Tests"
    ),
    .target(
      name: "ApiKit-OAuth",
      dependencies: ["ApiKit"],
      path: "ApiKit-OAuth/Sources"
    ),
    .testTarget(
      name: "ApiKit-OAuthTests",
      dependencies: ["ApiKit", "ApiKit-OAuth"],
      path: "ApiKit-OAuth/Tests"
    ),
    .target(
      name: "ApiKit-Google",
      dependencies: ["ApiKit", "ApiKit-OAuth", .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")],
      path: "ApiKit-Google/Sources"
    ),
    .testTarget(
      name: "ApiKit-GoogleTests",
      dependencies: ["ApiKit", "ApiKit-OAuth", "ApiKit-Google"],
      path: "ApiKit-Google/Tests"
    ),
  ]
)
