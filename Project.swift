import ProjectDescription

let project = Project(
    name: "MacMonitor",
    organizationName: "Dimillian",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.10",
            "MACOSX_DEPLOYMENT_TARGET": "26.0"
        ]
    ),
    targets: [
        .target(
            name: "MacMonitor",
            destinations: .macOS,
            product: .app,
            bundleId: "com.dimillian.MacMonitor",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": .string("MacMonitor"),
                "LSUIElement": .boolean(true)
            ]),
            sources: ["Sources/**"],
            resources: [
                "Resources/**"
            ]
        )
    ]
)
