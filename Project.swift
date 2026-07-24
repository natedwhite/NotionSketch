import ProjectDescription

let project = Project(
    name: "NotionSketch",
    settings: .settings(
        base: ["SWIFT_VERSION": .string("6.0")],
        configurations: [
            .debug(
                name: "Debug",
                settings: ["DEVELOPMENT_TEAM": .string("B25F8Q5S75")]
            ),
            .release(
                name: "Release",
                settings: ["DEVELOPMENT_TEAM": .string("B25F8Q5S75")]
            ),
        ]
    ),
    targets: [
        .target(
            name: "NotionSketch",
            destinations: Destinations.iOS,
            product: .app,
            bundleId: "com.notionsketch.app",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleURLTypes": [
                    [
                        "CFBundleTypeRole": "Editor",
                        "CFBundleURLName": "com.notionsketch.app",
                        "CFBundleURLSchemes": ["notionsketch"],
                    ],
                ],
                "UILaunchStoryboardName": "LaunchScreen",
                "UIApplicationSupportsIndirectInputEvents": true,
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                ],
                "UIFileSharingEnabled": true,
                "LSSupportsOpeningDocumentsInPlace": true,
            ]),
            sources: ["NotionSketch/**"],
            resources: [
                .glob(pattern: "NotionSketch/**/*.xcassets"),
                .glob(pattern: "NotionSketch/LaunchScreen.storyboard"),
            ],
            settings: .settings(
                base: [
                    "IPHONEOS_DEPLOYMENT_TARGET": .string("17.0"),
                    "ASSETCATALOG_COMPILER_APPICON_NAME": .string("AppIcon"),
                    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": .string("AccentColor"),
                    "CODE_SIGN_STYLE": .string("Automatic"),
                    "MARKETING_VERSION": .string("1.0"),
                    "CURRENT_PROJECT_VERSION": .string("1"),
                    "SWIFT_STRICT_CONCURRENCY": .string("complete"),
                    "SWIFT_EMIT_LOC_STRINGS": .string("YES"),
                    "SUPPORTS_MACCATALYST": .string("NO"),
                    "TARGETED_DEVICE_FAMILY": .string("2"),
                ]
            )
        )
    ]
)
