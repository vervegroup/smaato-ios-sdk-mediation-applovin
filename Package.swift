// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "SmaatoSDKAdaptersAppLovinWaterfall",
    platforms: [.iOS(.v12)],
    products: [
        .library(
            name: "SmaatoSDKAdaptersAppLovinWaterfall",
            targets: ["SmaatoSDKAdaptersAppLovinWaterfall"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/vervegroup/Smaato-ios-sdk-standalone.git", exact: "23.2.1"),
        .package(url: "https://github.com/AppLovin/AppLovin-MAX-Swift-Package.git", .upToNextMajor(from: "13.0.0"))
    ],
    targets: [
        .target(
            name: "SmaatoSDKAdaptersAppLovinWaterfall",
            dependencies: [
                .product(name: "SmaatoSDK", package: "Smaato-ios-sdk-standalone"),
                .product(name: "AppLovinSDK", package: "AppLovin-MAX-Swift-Package")
            ],
            path: "SmaatoSDKAdapters/ApplovinWaterfall",
            sources: [
                "SmaatoApplovinMediationAdapter.m"
            ],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath(".")
            ]
        )
    ]
)
