import PDFKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

// MARK: - Akta sprawy na telefonie
//
// Wezwanie przyszło pocztą, klient przyniósł postanowienie na rozprawę:
// „Skanuj” → kartki z aparatu stają się jednym PDF → nazwa i folder →
// „Zapisz w aktach”. Dokument ląduje w tych samych aktach co w panelu.
// Dotknięcie pozycji otwiera podgląd (QuickLook) bez wychodzenia z Emmy.

struct CaseDocumentsTab: View {

    let caseID: CaseID
    let caseTitle: String

    @EnvironmentObject private var dependencies: AppDependencies
    @State private var phase: LoadPhase<[CaseDocument]> = .idle
    @State private var isScanning = false
    @State private var isImporting = false
    @State private var pending: PendingDocument?
    @State private var previewURL: URL?
    @State private var openingID: String?

    private var store: CaseDocumentsRepository? {
        dependencies.repository as? CaseDocumentsRepository
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Akta sprawy")
                    .font(EmmaTypography.sectionTitle)
                    .foregroundStyle(EmmaTheme.ink)
                Spacer(minLength: 8)
                if store != nil { addMenu }
            }
            .frame(minHeight: EmmaSpacing.sectionHeaderMinHeight, alignment: .bottom)
            .padding(.top, EmmaSpacing.sectionTop)
            .padding(.bottom, EmmaSpacing.sectionBottom)

            content
        }
        .task(id: dependencies.dataVersion) { await load() }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScanner { images in
                isScanning = false
                guard !images.isEmpty else { return }
                Task { await prepareScan(images) }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            prepareImport(url)
        }
        .sheet(item: $pending) { document in
            SaveDocumentSheet(document: document, caseTitle: caseTitle) { name, folder in
                await upload(document, name: name, folder: folder)
            }
            .environmentObject(dependencies)
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in
            // Podgląd zamknięty — kopia dokumentu nie zostaje w telefonie.
            if new == nil, let old { try? FileManager.default.removeItem(at: old) }
        }
    }

    // MARK: Treść

    @ViewBuilder
    private var content: some View {
        if store == nil {
            emptyCard(
                "Akta w panelu",
                "Ten serwer nie udostępnia jeszcze akt aplikacji. Dokumenty sprawy są w panelu kancelarii."
            )
        } else {
            switch phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .failed(let failure):
                emptyCard("Nie udało się wczytać akt", failure.message)
            case .loaded(let documents) where documents.isEmpty:
                EmptyState(
                    systemImage: "doc.viewfinder",
                    title: "Brak dokumentów",
                    message: "Zeskanuj wezwanie, postanowienie albo pełnomocnictwo — trafi do akt tej sprawy.",
                    actionTitle: DocumentScanner.isAvailable ? "Skanuj dokument" : "Wybierz plik",
                    action: { startAdding() }
                )
                .frame(maxWidth: .infinity)
                .background(EmmaTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                        .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
                }
            case .loaded(let documents):
                VStack(spacing: 8) {
                    ForEach(documents) { document in
                        row(document)
                    }
                }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            if DocumentScanner.isAvailable {
                Button { isScanning = true } label: { Label("Skanuj dokument", systemImage: "doc.viewfinder") }
            }
            Button { isImporting = true } label: { Label("Wybierz z Plików", systemImage: "folder") }
        } label: {
            Label("Dodaj", systemImage: "plus")
                .font(EmmaTypography.caption(.medium))
                .foregroundStyle(EmmaTheme.accent)
                .frame(minHeight: EmmaSpacing.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("case-documents-add")
    }

    private func row(_ document: CaseDocument) -> some View {
        Button {
            Task { await open(document) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: document.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .font(EmmaTypography.ui(14, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle(document))
                        .font(EmmaTypography.caption())
                        .foregroundStyle(EmmaTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if openingID == document.id {
                    ProgressView()
                } else if let status = document.statusLabel {
                    Text(status)
                        .font(EmmaTypography.caption(.medium))
                        .foregroundStyle(EmmaTheme.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityHint("Otwiera podgląd dokumentu")
    }

    /// „Pisma · 1 października · 340 KB”.
    private func subtitle(_ document: CaseDocument) -> String {
        let day = dependencies.dateText.dayTitle(AppDependencies.localDate(from: document.uploadedAt))
        return [document.folder, day, document.sizeText].joined(separator: " · ")
    }

    private func emptyCard(_ title: String, _ message: String) -> some View {
        EmptyState(systemImage: "folder", title: title, message: message)
            .frame(maxWidth: .infinity)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
    }

    // MARK: Działania

    private func startAdding() {
        if DocumentScanner.isAvailable {
            isScanning = true
        } else {
            isImporting = true
        }
    }

    private func load() async {
        guard let store else { return }
        if !phase.hasLoaded { phase = .loading }
        do {
            phase = .loaded(try await store.caseDocuments(caseID: caseID))
        } catch {
            if let message = phase.recordFailure(error, fallback: "Nie udało się wczytać akt.") {
                dependencies.showToast(message)
            }
        }
    }

    private func prepareScan(_ images: [UIImage]) async {
        let data = await Task.detached(priority: .userInitiated) { ScanPDF.make(from: images) }.value
        guard let data else {
            dependencies.showToast("Nie udało się złożyć skanu w PDF.")
            return
        }
        pending = PendingDocument(
            suggestedName: CaseDocumentNaming.scanFileName(title: nil, at: Date(), calendar: FirmDateTime.calendar),
            mime: "application/pdf",
            data: data,
            pageCount: images.count
        )
    }

    private func prepareImport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            dependencies.showToast("Nie udało się odczytać pliku.")
            return
        }
        let type = UTType(filenameExtension: url.pathExtension)
        pending = PendingDocument(
            suggestedName: url.lastPathComponent,
            mime: type?.preferredMIMEType ?? "application/octet-stream",
            data: data,
            pageCount: nil
        )
    }

    /// Zwraca komunikat błędu do arkusza albo `nil` po zapisie.
    private func upload(_ document: PendingDocument, name: String, folder: CaseDocumentFolder) async -> String? {
        guard let store else { return "Ten serwer nie przyjmuje jeszcze dokumentów z aplikacji." }
        guard document.data.count <= ScanPDF.maxUploadBytes else {
            return "Plik ma ponad 10 MB — zeskanuj mniej stron naraz."
        }
        let outcome = await dependencies.submit(fallback: "Nie udało się zapisać dokumentu w aktach.") {
            try await store.uploadCaseDocument(
                caseID: caseID,
                fileName: name,
                mime: document.mime,
                data: document.data,
                folder: folder
            )
        }
        guard outcome.value != nil else { return outcome.errorMessage }
        EmmaHaptics.success()
        dependencies.showToast("„\(name)” jest w aktach sprawy.")
        return nil
    }

    private func open(_ document: CaseDocument) async {
        guard let store, openingID == nil else { return }
        openingID = document.id
        defer { openingID = nil }
        do {
            let data = try await store.documentData(id: document.id)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("akta", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let base = (document.name as NSString).deletingPathExtension
            let url = directory.appendingPathComponent("\(base).\(document.fileExtension)")
            // Akta są poufne: kopia do podglądu jest nieczytelna przy blokadzie.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            previewURL = url
        } catch {
            dependencies.showToast(ScreenLoad.message(for: error, fallback: "Nie udało się otworzyć dokumentu."))
        }
    }
}

// MARK: - Dokument czekający na zapis

struct PendingDocument: Identifiable {
    let id = UUID()
    let suggestedName: String
    let mime: String
    let data: Data
    /// Liczba stron skanu; `nil` dla pliku z Plików.
    let pageCount: Int?
}

/// „Do akt”: nazwa i folder, potem jeden przycisk.
private struct SaveDocumentSheet: View {
    let document: PendingDocument
    let caseTitle: String
    let onSave: (String, CaseDocumentFolder) async -> String?

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var folder: CaseDocumentFolder = .documents
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Do akt: \(caseTitle)") { dismiss() }

            if let pages = document.pageCount {
                Text("\(pages) \(EmmaPlural.form(pages, "strona", "strony", "stron")) · PDF")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
                    .padding(.bottom, 12)
            }

            LabeledField("Nazwa dokumentu") {
                TextField("np. Wezwanie na przesłuchanie", text: $name)
                    .emmaFieldStyle()
                    .accessibilityIdentifier("document-name")
            }

            LabeledField("Folder") {
                ChipFlow {
                    ForEach([CaseDocumentFolder.documents, .filings, .evidence, .other]) { option in
                        ChoiceChip(title: option.rawValue, isSelected: folder == option) { folder = option }
                    }
                }
            }
            .padding(.bottom, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.pillDangerText)
                    .padding(.bottom, 10)
            }

            PrimaryButton("Zapisz w aktach", systemImage: "tray.and.arrow.down", isEnabled: !trimmedName.isEmpty, isLoading: isSaving) {
                Task { await save() }
            }
            .accessibilityIdentifier("document-save")
        }
        .padding(20)
        .presentationDetents([.medium])
        .onAppear { name = document.suggestedName }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nazwa z rozszerzeniem — panel i podgląd rozpoznają typ po nazwie.
    private var fileName: String {
        let suffix = document.mime == "application/pdf" ? ".pdf" : ""
        return suffix.isEmpty || trimmedName.lowercased().hasSuffix(suffix) ? trimmedName : trimmedName + suffix
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = await onSave(fileName, folder)
        isSaving = false
        if errorMessage == nil { dismiss() }
    }
}

// MARK: - Skaner i PDF

/// Kamera dokumentów z VisionKit: wykrywa kartkę, prostuje i wyostrza.
private struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    @MainActor static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void

        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}

enum ScanPDF {
    /// Limit pliku po stronie serwera.
    static let maxUploadBytes = 10 * 1024 * 1024
    /// Dłuższy bok strony w pikselach — ok. 200 dpi dla A4, czytelne pismo
    /// przy kilkuset KB na stronę.
    private static let maxPixel: CGFloat = 2000

    /// Strony skanu jako jeden PDF; obraz strony jako JPEG, żeby skan
    /// kilku kartek mieścił się w limicie serwera.
    static func make(from images: [UIImage]) -> Data? {
        let document = PDFDocument()
        for (index, image) in images.enumerated() {
            guard let compact = compressed(image), let page = PDFPage(image: compact) else { return nil }
            document.insert(page, at: index)
        }
        return document.dataRepresentation()
    }

    private static func compressed(_ image: UIImage) -> UIImage? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let factor = min(1, maxPixel / max(longest, 1))
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.6).flatMap(UIImage.init(data:))
    }
}
