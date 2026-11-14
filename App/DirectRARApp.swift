import SwiftUI
import UniformTypeIdentifiers

@main
struct DirectRARApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct Picker: UIViewControllerRepresentable {
    var folder: Bool
    var selected: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(selected) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: folder ? [.folder] : [.data], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL) -> Void
        init(_ selected: @escaping (URL) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { selected(url) }
        }
    }
}

final class Work: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var lastUpdate = Date.distantPast
    var report: ((Int64, Int64, String) -> Void)?
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func progress(_ read: Int64, _ written: Int64, _ name: String) -> Int32 {
        lock.lock()
        let stop = cancelled
        let now = Date()
        let update = now.timeIntervalSince(lastUpdate) > 0.15
        if update { lastUpdate = now }
        lock.unlock()
        if update { report?(read, written, name) }
        return stop ? 1 : 0
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var source: URL?
    @Published var destination: URL?
    @Published var running = false
    @Published var fraction = 0.0
    @Published var status = "Seleccioná un archivo y una carpeta."
    @Published var current = ""
    @Published var written: Int64 = 0
    private var work: Work?
    func cancel() { work?.cancel(); status = "Cancelando…" }
    func start() {
        guard !running, let source, let destination else { return }
        running = true; fraction = 0; written = 0; current = ""; status = "Preparando…"
        UIApplication.shared.isIdleTimerDisabled = true
        let job = Work(); work = job
        DispatchQueue.global(qos: .userInitiated).async {
            let sourceAccess = source.startAccessingSecurityScopedResource()
            let folderAccess = destination.startAccessingSecurityScopedResource()
            defer {
                if sourceAccess { source.stopAccessingSecurityScopedResource() }
                if folderAccess { destination.stopAccessingSecurityScopedResource() }
            }
            var coordinationError: NSError?
            var message = "No se pudo acceder al archivo."
            var success = false
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: .forMerging, error: &coordinationError) { input, folder in
                let size = (try? input.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let output = folder.appendingPathComponent("Extraido-" + UUID().uuidString, isDirectory: true)
                job.report = { read, bytes, name in
                    DispatchQueue.main.async {
                        self.fraction = size > 0 ? min(0.99, Double(read) / Double(size)) : 0
                        self.written = bytes; self.current = name; self.status = "Extrayendo…"
                    }
                }
                do {
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
                    var error = [CChar](repeating: 0, count: 2048)
                    let context = Unmanaged.passUnretained(job).toOpaque()
                    let result = dr_extract(input.path, output.path, { context, read, written, name in
                        guard let context else { return 1 }
                        let work = Unmanaged<Work>.fromOpaque(context).takeUnretainedValue()
                        return work.progress(read, written, name.map { String(cString: $0) } ?? "")
                    }, context, &error, 2048)
                    if result == 0 {
                        success = true; message = "Listo: \(output.lastPathComponent)"
                    } else {
                        message = result == 2 ? "Extracción cancelada." : String(cString: error)
                        do { try FileManager.default.removeItem(at: output) }
                        catch { message += " Quedaron archivos parciales en \(output.lastPathComponent)." }
                    }
                } catch { message = error.localizedDescription }
            }
            if let coordinationError { message = coordinationError.localizedDescription }
            let finalMessage = message; let completed = success
            DispatchQueue.main.async {
                self.status = finalMessage; self.running = false; self.work = nil
                if completed { self.fraction = 1 }
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = Model()
    @State private var picker: Selection?
    enum Selection: String, Identifiable { case file, folder; var id: String { rawValue } }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "archivebox.fill").font(.system(size: 52)).foregroundStyle(.orange)
                Text("Extraé directamente").font(.largeTitle.bold())
                Text("El original se lee donde está. Lo extraído se guarda en una carpeta nueva dentro del destino.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.source?.lastPathComponent ?? "Sin archivo", systemImage: "doc.zipper")
                    Label(model.destination?.lastPathComponent ?? "Sin destino", systemImage: "folder")
                }.font(.callout).lineLimit(2)
                ProgressView(value: model.fraction)
                Text(model.status).font(.headline)
                if model.running {
                    Text(ByteCountFormatter.string(fromByteCount: model.written, countStyle: .file) + " escritos").monospacedDigit()
                    Text(model.current).font(.caption).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("Mantené la app abierta. RAR/RAR5 sin contraseña en esta primera versión. Los archivos en iCloud pueden necesitar descargarse.").font(.footnote).foregroundStyle(.secondary)
                if model.running {
                    Button("Cancelar", role: .destructive) { model.cancel() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                } else {
                    Button("1 · Elegir RAR") { picker = .file }.buttonStyle(.bordered)
                    Button("2 · Elegir carpeta de destino") { picker = .folder }.buttonStyle(.bordered)
                    Button { model.start() } label: { Text("Extraer").frame(maxWidth: .infinity).padding(.vertical, 8) }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(model.source == nil || model.destination == nil)
                }
            }.padding(24).navigationTitle("DirectRAR").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $picker) { selection in
                Picker(folder: selection == .folder) { url in
                    if selection == .folder { model.destination = url } else { model.source = url }
                    picker = nil
                }
            }
        }
    }
}
