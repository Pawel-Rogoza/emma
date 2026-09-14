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
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "Emma", targets: ["Emma"])
    ],
    targets: [
        .target(
            name: "Emma",
            path: "Emma",
            // Warstwy zależne od SwiftUI/UIKit są tu jawnie wykluczone, a nie
            // „przypadkiem pominięte”: dzięki temu `swift build` nie zgłasza
            // nieobsłużonych plików, a lista tego, co da się sprawdzić na Linuksie,
            // jest zamknięta i widoczna.
            exclude: [
                "App",
                "DesignSystem",
                "Features",
                "VoiceAdapters",
                // Zasoby trafiają do aplikacji iOS; pakiet logiki ich nie potrzebuje.
                "Resources"
            ],
            // Wyłącznie warstwy niezależne od SwiftUI/UIKit/AVFoundation.
            // `Core/Auth/BiometricAuthenticator.swift` (LocalAuthentication)
            // zostaje poza pakietem — stąd wskazujemy pojedyncze pliki, a nie
            // cały katalog.
            sources: [
                "Core/Auth/MobileAuthModels.swift",
                "Core/Auth/MobileAuthClient.swift",
                "Core/Auth/MobileSessionKeeper.swift",
                "Core/Domain",
                "Core/Data",
                "Core/Voice/VoiceEvents.swift",
                "Core/Voice/VoiceServices.swift",
                "Core/Voice/VoiceStateReducer.swift",
                "Core/Voice/VoiceSessionCoordinator.swift",
                "Core/Voice/MockVoiceServices.swift",
                "PreviewSupport"
            ]
        ),
        // Narzędzie deweloperskie: wypisuje dane demo jako JSON na potrzeby podglądu
        // na Linuksie (`scripts/build-preview.py`). Nie wchodzi do aplikacji iOS —
        // `project.yml` buduje target z katalogu `Emma`, więc ten katalog jest poza nim.
        .executableTarget(
            name: "EmmaPreviewExport",
            dependencies: ["Emma"],
            path: "EmmaPreview"
        ),
        .testTarget(
            name: "EmmaLogicTests",
            dependencies: ["Emma"],
            path: "EmmaTests",
            sources: ["Logic"]
        )
    ]
)
