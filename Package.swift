// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LLMPrices",
    products: [
        .library(name: "LLMPrices", targets: ["LLMPrices"]),
    ],
    targets: [
        .target(name: "LLMPrices"),
        .testTarget(name: "LLMPricesTests", dependencies: ["LLMPrices"]),
    ]
)
