// swift-tools-version:5.9
//
// Pakiet służy JEDNEMU celowi: pozwala skompilować i przetestować **logikę** Emmy
// w środowisku bez macOS/Xcode (Swift na Linuksie). Nie jest alternatywą dla
// projektu Xcode i nie buduje SwiftUI — widoki są wykluczone, bo SwiftUI istnieje
// tylko na platformach Apple.
//
// Ten sam kod źródłowy trafia do targetu aplikacji iOS przez `project.yml`,
// więc nie ma dwóch kopii logiki.
//
//   swift build      # kompiluje logikę
//   swift test       # uruchamia testy reguł z §12.2 planu
//
// Na macOS można go zignorować i korzystać z ios/Emma.xcodeproj.

import PackageDescription

let package = Package(
    name: "EmmaCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "Emma", targets: ["Emma"])
    ],
    targets: [
        .target(
            name: "Emma",
            path: "Emma",
            // Wyłącznie warstwy niezależne od SwiftUI/UIKit/AVFoundation.
            sources: [
                "Core/Domain",
                "Core/Voice/VoiceEvents.swift",
                "Core/Voice/VoiceServices.swift",
                "Core/Voice/VoiceStateReducer.swift",
                "Core/Voice/VoiceSessionCoordinator.swift",
                "Core/Voice/MockVoiceServices.swift",
                "PreviewSupport"
            ]
        ),
        .testTarget(
            name: "EmmaLogicTests",
            dependencies: ["Emma"],
            path: "EmmaTests",
            sources: ["Logic"]
        )
    ]
)
