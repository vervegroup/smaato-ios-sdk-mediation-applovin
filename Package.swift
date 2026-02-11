// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "SmaatoSDKApplovinWaterfallAdapter",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(
            name: "SmaatoSDKApplovinWaterfallAdapter",
            targets: ["SmaatoSDKApplovinWaterfallAdapter"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/vervegroup/Smaato-ios-sdk-standalone.git", branch: "VMI-1490-add-spm-support"),
        .package(url: "https://github.com/AppLovin/AppLovin-MAX-Swift-Package", .upToNextMajor(from: "10.3.6"))
    ],
    targets: [
        .target(
            name: "SmaatoSDKApplovinWaterfallAdapter",
            dependencies: [
                .product(name: "SmaatoSDK", package: "SmaatoSDKStandalone"),
                .product(name: "AppLovinSDK", package: "AppLovin-MAX-Swift-Package")
            ],
            path: "SmaatoSDKAdapters/ApplovinWaterfall",
            sources: [
                "SmaatoApplovinMediationAdapter.m"
            ],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath(".")
            ],
            linkerSettings: [
                .unsafeFlags(["-ObjC"])
            ]
        )
    ]
)
