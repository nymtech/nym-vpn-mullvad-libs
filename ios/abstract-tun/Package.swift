// swift-tools-version:5.7.
import PackageDescription
import Foundation

let package = Package(
            name: "AbstractTun",
            platforms: [
                .iOS(.v13)
            ],

            products: [
                .library(
                        name: "AbstractTun",
                        targets: ["AbstractTun"],
                    )
            ],

        )
