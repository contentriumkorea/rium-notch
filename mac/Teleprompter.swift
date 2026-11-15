import AppKit

@_silgen_name("rium_teleprompter_save") private func promptSave(_ root: UnsafePointer<CChar>, _ data: UnsafeRawPointer?, _ length: Int) -> Int32
@_silgen_name("rium_teleprompter_load") private func promptLoad(_ root: UnsafePointer<CChar>, _ length: UnsafeMutablePointer<Int>) -> UnsafeMutablePointer<UInt8>?
@_silgen_name("rium_teleprompter_free") private func promptFree(_ data: UnsafeMutablePointer<UInt8>?, _ length: Int)
@_silgen_name("rium_teleprompter_chapters") private func promptChapterJSON(_ data: UnsafeRawPointer?, _ length: Int) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_teleprompter_free_string") private func promptFreeString(_ data: UnsafeMutablePointer<CChar>?)

private struct PromptChapter: Decodable { let title: String; let offset: Int }
private func promptChapters(_ text: String) -> [PromptChapter] {
    let data = Data(text.utf8)
    guard let raw = data.withUnsafeBytes({ promptChapterJSON($0.baseAddress, $0.count) }) else { return [] }
    defer { promptFreeString(raw) }
    return (try? JSONDecoder().decode([PromptChapter].self, from: Data(bytes: raw, count: strlen(raw)))) ?? []
}
func promptSearchRange(_ text: String, query: String, selected: NSRange, backwards: Bool) -> NSRange? {
    guard !query.isEmpty else { return nil }
    let source = text as NSString, length = source.length
    let location = selected.location == NSNotFound ? 0 : min(max(0, selected.location), length)
    let selectionLength = min(max(0, selected.length), length - location)
    let start = backwards ? location : location + selectionLength
    let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .diacriticInsensitive, .backwards] : [.caseInsensitive, .diacriticInsensitive]
    let first = backwards ? NSRange(location: 0, length: start) : NSRange(location: start, length: length - start)
    let second = backwards ? NSRange(location: start, length: length - start) : NSRange(location: 0, length: start)
    let found = source.range(of: query, options: options, range: first)
    if found.location != NSNotFound { return found }
    let wrapped = source.range(of: query, options: options, range: second)
    return wrapped.location == NSNotFound ? nil : wrapped
}

final class TeleprompterController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private var window: NSWindow?
    private var scrollView: NSScrollView?
    private var textView: NSTextView?
    private var timer: Timer?
    private var playButton: NSButton?
    private var speedSlider: NSSlider?
    private var fontSlider: NSSlider?
    private var fontLabel: NSTextField?
    private var statusLabel: NSTextField?
    private var searchField: NSSearchField?
    private var searchStatus: NSTextField?
    private var chaptersButton: NSPopUpButton?
    private var saveWork: DispatchWorkItem?
    private var chapterWork: DispatchWorkItem?
    private var chapterGeneration = 0
    private let saveQueue = DispatchQueue(label: "app.rium.notch.teleprompter.save", qos: .utility)
    private var revision = 0
    private var dirty = false
    private var canSave = false
    private let root: URL
    private let preferences: UserDefaults

    init(root: URL? = nil, preferences: UserDefaults = .standard) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.root = root ?? support.appendingPathComponent("Rium Notch", isDirectory: true)
        self.preferences = preferences
        super.init()
    }
    private func setting(_ key: String, range: ClosedRange<Double>, defaultValue: Double) -> Double {
        guard let value = preferences.object(forKey: key) as? NSNumber, value.doubleValue.isFinite, range.contains(value.doubleValue) else { return defaultValue }
        return value.doubleValue
    }
    private func loadScript() -> String? {
        var size = 0
        guard let bytes = root.path.withCString({ promptLoad($0, &size) }) else { return nil }
        defer { promptFree(bytes, size) }
        return String(data: Data(bytes: bytes, count: size), encoding: .utf8)
    }
    private func saveScript(_ data: Data) -> Int32 {
        root.path.withCString { path in data.withUnsafeBytes { bytes in promptSave(path, bytes.baseAddress, bytes.count) } }
    }
    private func reportSave(_ result: Int32, revision savedRevision: Int) {
        guard revision == savedRevision else { return }
        if result == 0 { dirty = false; statusLabel?.stringValue = "원고 자동 저장" }
        else { statusLabel?.stringValue = result == -2 ? "원고가 너무 커서 저장하지 못했습니다." : "원고를 저장하지 못했습니다." }
    }
    func textDidChange(_ notification: Notification) {
        guard let textView = textView else { return }
        scheduleChapters(textView.string)
        guard canSave else { return }
        dirty = true; revision += 1
        let current = revision, data = Data(textView.string.utf8)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.saveQueue.async { [weak self] in
                guard let self = self else { return }
                let result = self.saveScript(data)
                DispatchQueue.main.async { [weak self] in self?.reportSave(result, revision: current) }
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    private func scheduleChapters(_ text: String) {
        chapterGeneration += 1; let generation = chapterGeneration
        chapterWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.global(qos: .utility).async {
                let chapters = promptChapters(text)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.chapterGeneration == generation, let button = self.chaptersButton else { return }
                    button.removeAllItems(); button.addItem(withTitle: "구간 이동")
                    for chapter in chapters {
                        button.addItem(withTitle: chapter.title)
                        button.lastItem?.representedObject = NSNumber(value: chapter.offset)
                    }
                    button.isEnabled = !chapters.isEmpty
                }
            }
        }
        chapterWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func flush() {
        saveWork?.cancel(); saveWork = nil
        guard canSave, dirty, let textView = textView else { return }
        revision += 1; let current = revision, data = Data(textView.string.utf8)
        let result = saveQueue.sync { saveScript(data) }
        reportSave(result, revision: current)
    }

    func show() {
        if let window = window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 420), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Rium Notch 프롬프터"; window.center(); window.level = .floating; window.delegate = self
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 400, height: 240)
        let rootView = NSView(); rootView.translatesAutoresizingMaskIntoConstraints = false; window.contentView = rootView
        let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.hasVerticalScroller = true; scroll.drawsBackground = true; scroll.backgroundColor = .black
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 680, height: 330)); text.isRichText = false; text.isEditable = true
        text.backgroundColor = .black; text.textColor = .white; text.insertionPointColor = .white
        text.font = .systemFont(ofSize: setting("rium.prompt.fontSize", range: 18...72, defaultValue: 30))
        text.textContainerInset = NSSize(width: 24, height: 20); text.autoresizingMask = [.width]; text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true; scroll.documentView = text
        let stored = loadScript(); canSave = stored != nil; text.string = stored ?? ""; text.delegate = self
        let play = NSButton(title: "스크롤 시작", target: self, action: #selector(toggle))
        let speed = NSSlider(value: setting("rium.prompt.speed", range: 5...120, defaultValue: 30), minValue: 5, maxValue: 120, target: self, action: #selector(changeSpeed))
        speed.setAccessibilityLabel("스크롤 속도")
        let size = NSSlider(value: setting("rium.prompt.fontSize", range: 18...72, defaultValue: 30), minValue: 18, maxValue: 72, target: self, action: #selector(changeFontSize))
        size.setAccessibilityLabel("글자 크기")
        speed.widthAnchor.constraint(equalToConstant: 80).isActive = true; size.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let fontLabel = NSTextField(labelWithString: "글자 \(Int(size.doubleValue))")
        let toolbar = NSStackView(views: [play, NSTextField(labelWithString: "속도"), speed, fontLabel, size]); toolbar.orientation = .horizontal; toolbar.spacing = 8; toolbar.translatesAutoresizingMaskIntoConstraints = false
        let search = NSSearchField(); search.placeholderString = "원고 검색"; search.setAccessibilityLabel("원고 검색"); search.target = self; search.action = #selector(findNext)
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        search.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
        let previous = NSButton(title: "이전", target: self, action: #selector(findPrevious)); previous.setAccessibilityLabel("이전 검색 결과")
        let next = NSButton(title: "다음", target: self, action: #selector(findNext)); next.setAccessibilityLabel("다음 검색 결과")
        let chapters = NSPopUpButton(); chapters.addItem(withTitle: "구간 이동"); chapters.isEnabled = false; chapters.target = self; chapters.action = #selector(jumpToChapter); chapters.setAccessibilityLabel("원고 구간 이동")
        chapters.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let navigation = NSStackView(views: [search, previous, next, chapters]); navigation.orientation = .horizontal; navigation.spacing = 6; navigation.translatesAutoresizingMaskIntoConstraints = false
        let status = NSTextField(labelWithString: canSave ? "원고 자동 저장" : "저장된 원고를 읽지 못해 자동 저장을 중지했습니다.")
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.translatesAutoresizingMaskIntoConstraints = false
        let searchStatus = NSTextField(labelWithString: "구간 제목: # 제목"); searchStatus.font = .systemFont(ofSize: 11); searchStatus.textColor = .secondaryLabelColor; searchStatus.alignment = .right; searchStatus.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(scroll); rootView.addSubview(navigation); rootView.addSubview(toolbar); rootView.addSubview(status); rootView.addSubview(searchStatus)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: rootView.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: rootView.trailingAnchor), scroll.topAnchor.constraint(equalTo: rootView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: navigation.topAnchor, constant: -8),
            navigation.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12), navigation.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -12), navigation.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -5),
            toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12), toolbar.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -12),
            toolbar.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -5),
            status.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 12), status.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -7),
            searchStatus.leadingAnchor.constraint(greaterThanOrEqualTo: status.trailingAnchor, constant: 8), searchStatus.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12), searchStatus.centerYAnchor.constraint(equalTo: status.centerYAnchor)
        ])
        self.window = window; self.scrollView = scroll; self.textView = text; self.playButton = play; self.speedSlider = speed; self.fontSlider = size; self.fontLabel = fontLabel; self.statusLabel = status
        self.searchField = search; self.searchStatus = searchStatus; self.chaptersButton = chapters; scheduleChapters(text.string)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func changeSpeed() { if let value = speedSlider?.doubleValue { preferences.set(value, forKey: "rium.prompt.speed") } }
    @objc private func findNext() { find(backwards: false) }
    @objc private func findPrevious() { find(backwards: true) }
    private func find(backwards: Bool) {
        guard let textView = textView, let query = searchField?.stringValue, !query.isEmpty else { searchStatus?.stringValue = "검색어를 입력하세요"; return }
        guard let found = promptSearchRange(textView.string, query: query, selected: textView.selectedRange(), backwards: backwards) else { searchStatus?.stringValue = "검색 결과가 없습니다"; return }
        textView.setSelectedRange(found); textView.scrollRangeToVisible(found); searchStatus?.stringValue = "검색 결과로 이동"
    }
    @objc private func jumpToChapter() {
        guard let offset = chaptersButton?.selectedItem?.representedObject as? NSNumber, let textView = textView else { return }
        let location = min(max(0, offset.intValue), (textView.string as NSString).length)
        let range = NSRange(location: location, length: 0); textView.setSelectedRange(range); textView.scrollRangeToVisible(range)
    }
    @objc private func changeFontSize() {
        guard let value = fontSlider?.doubleValue else { return }
        textView?.font = .systemFont(ofSize: value); fontLabel?.stringValue = "글자 \(Int(value))"
        preferences.set(value, forKey: "rium.prompt.fontSize")
    }
    @objc private func toggle() {
        if timer != nil { stop(); return }
        playButton?.title = "스크롤 정지"
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let scroll = self.scrollView, let content = scroll.documentView else { return }
            let clip = scroll.contentView, limit = max(0, content.bounds.height - clip.bounds.height)
            let next = min(limit, clip.bounds.origin.y + CGFloat(self.speedSlider?.doubleValue ?? 30) * 0.05)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: next)); scroll.reflectScrolledClipView(clip)
            if next >= limit { self.stop() }
        }
    }
    private func stop() { timer?.invalidate(); timer = nil; playButton?.title = "스크롤 시작" }
    func windowWillClose(_ notification: Notification) { stop(); flush() }
}
