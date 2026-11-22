import AppKit
import SwiftUI

@_silgen_name("rium_notes_load") private func notesLoad(_ root: UnsafePointer<CChar>, _ length: UnsafeMutablePointer<Int>) -> UnsafeMutablePointer<UInt8>?
@_silgen_name("rium_notes_save") private func notesSave(_ root: UnsafePointer<CChar>, _ data: UnsafeRawPointer?, _ length: Int) -> Int32
@_silgen_name("rium_notes_free") private func notesFree(_ bytes: UnsafeMutablePointer<UInt8>?, _ length: Int)
@_silgen_name("rium_notes_save_delay") private func notesSaveDelay() -> Double

struct RiumNote: Codable, Identifiable {
    let id: UUID
    var title: String
    var text: String
    let createdAt: Date
    var updatedAt: Date
    var displayTitle: String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "제목 없는 메모" : clean
    }
    var isEmpty: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

final class NotesModel: ObservableObject {
    @Published private(set) var entries: [RiumNote] = []
    @Published private(set) var ready = false
    @Published private(set) var error = ""
    @Published private(set) var dirty = false
    private let root: URL
    private let persistent: Bool
    private let queue = DispatchQueue(label: "app.rium.notch.notes.store", qos: .utility)
    private var pending: DispatchWorkItem?
    private var revision = 0
    private var draftID: UUID?

    init(startServices: Bool, root: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.root = root ?? support.appendingPathComponent("Rium Notch", isDirectory: true)
        persistent = startServices
        if !startServices { ready = true; return }
        queue.async { [weak self] in
            guard let self = self else { return }
            var length = 0
            let decoded: [RiumNote]? = self.root.path.withCString { path in
                guard let bytes = notesLoad(path, &length) else { return nil }
                defer { notesFree(bytes, length) }
                return try? JSONDecoder().decode([RiumNote].self, from: Data(bytes: bytes, count: length))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard let decoded = decoded else { self.error = "메모를 읽지 못해 저장을 중지했습니다."; return }
                self.entries = decoded; self.ready = true
            }
        }
    }

    func create() -> UUID? {
        guard ready, entries.count < 500 else { if ready { error = "메모는 최대 500개까지 저장할 수 있습니다." }; return nil }
        discardEmptyDraft()
        let now = Date(), note = RiumNote(id: UUID(), title: "", text: "", createdAt: now, updatedAt: now)
        entries.insert(note, at: 0); draftID = note.id
        return note.id
    }

    func update(_ id: UUID, title: String? = nil, text: String? = nil) {
        guard ready, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let title = title ?? entries[index].title
        let text = text ?? entries[index].text
        guard entries[index].title != title || entries[index].text != text else { return }
        entries[index].title = title; entries[index].text = text; entries[index].updatedAt = Date()
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard ready, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        if draftID == id { draftID = nil }
        if persistent {
            dirty = true
            flush()
        }
    }

    private func discardEmptyDraft() {
        guard let id = draftID else { return }
        draftID = nil
        if let index = entries.firstIndex(where: { $0.id == id && $0.isEmpty }) {
            entries.remove(at: index)
            scheduleSave()
        }
    }

    private func scheduleSave() {
        guard persistent else { return }
        dirty = true; revision &+= 1
        let savedRevision = revision
        let snapshot = entries
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.queue.async { [weak self] in
                guard let self = self else { return }
                let result = self.write(snapshot)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.revision == savedRevision else { return }
                    self.applySaveResult(result)
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + notesSaveDelay(), execute: work)
    }

    private func write(_ snapshot: [RiumNote]) -> Int32 {
        guard let data = try? JSONEncoder().encode(snapshot) else { return -1 }
        return root.path.withCString { path in data.withUnsafeBytes { notesSave(path, $0.baseAddress, $0.count) } }
    }

    private func applySaveResult(_ result: Int32) {
        if result == 0 { dirty = false; error = "" }
        else { error = result == -2 ? "메모가 너무 커서 저장하지 못했습니다." : "메모를 저장하지 못했습니다." }
    }

    private func flush() {
        pending?.cancel()
        pending = nil
        guard persistent, ready, dirty else { return }
        // Ignore completion callbacks from older writes already on the serial queue.
        revision &+= 1
        let snapshot = entries
        applySaveResult(queue.sync { write(snapshot) })
    }

    func finishEditing() {
        discardEmptyDraft()
        flush()
    }
}

// shortcut: layout and editing transitions need comparison with the reference.
struct NotesPage: View {
    @ObservedObject var model: Model
    @ObservedObject var notes: NotesModel
    @State private var selectedID: UUID?
    @State private var query = ""
    @State private var confirmingDelete = false
    @FocusState private var titleFocused: Bool

    init(model: Model, notes: NotesModel) { self.model = model; self.notes = notes }

    private var selected: RiumNote? { notes.entries.first { $0.id == selectedID } }
    private var filtered: [RiumNote] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.entries.filter { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) || $0.text.localizedCaseInsensitiveContains(text) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    private func finish() {
        titleFocused = false; selectedID = nil; model.setNotesEditing(false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if selectedID != nil { Button("뒤로", action: finish).buttonStyle(.plain) }
                Text("메모").font(.system(size: 15, weight: .semibold))
                Spacer()
                if selectedID == nil {
                    Button { if let id = notes.create() { selectedID = id; model.setNotesEditing(true); titleFocused = true } } label: { Image(systemName: "plus") }
                        .disabled(!notes.ready).help("새 메모")
                } else {
                    Button("삭제") { confirmingDelete = true }.buttonStyle(.plain)
                    Button("완료", action: finish).buttonStyle(.plain)
                }
            }
            if !notes.error.isEmpty { Text(notes.error).font(.caption).foregroundStyle(.orange) }
            if !notes.ready {
                Text(notes.error.isEmpty ? "메모 불러오는 중…" : "기존 메모 파일을 확인해 주세요.").foregroundStyle(.secondary)
            } else if let note = selected {
                TextField("제목", text: Binding(get: { selected?.title ?? "" }, set: { notes.update(note.id, title: $0) }))
                    .textFieldStyle(.plain).font(.system(size: 15, weight: .semibold)).focused($titleFocused)
                TextEditor(text: Binding(get: { selected?.text ?? "" }, set: { notes.update(note.id, text: $0) }))
                    .font(.system(size: 13)).scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                if notes.dirty { Text("저장 중…").font(.caption2).foregroundStyle(.secondary) }
            } else {
                TextField("메모 검색", text: $query).textFieldStyle(.roundedBorder)
                if filtered.isEmpty { Text(query.isEmpty ? "메모가 없습니다." : "검색 결과가 없습니다.").foregroundStyle(.secondary).font(.caption) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filtered) { note in
                            Button { selectedID = note.id; model.setNotesEditing(true) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(note.text.isEmpty ? note.updatedAt.formatted(date: .abbreviated, time: .shortened) : note.text)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .confirmationDialog("이 메모를 삭제할까요?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { if let id = selectedID { notes.remove(id) }; finish() }
        }
        .onDisappear { finish() }
    }
}
