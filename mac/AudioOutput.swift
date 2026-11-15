import SwiftUI
import CoreAudio

struct AudioOutputDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
}

// Reads the system output list locally. The default output is changed only
// when the user explicitly chooses a device in the music panel.
final class AudioOutputModel: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var current: AudioDeviceID = AudioObjectID(kAudioObjectUnknown)
    @Published private(set) var error = ""

    func refresh() {
        var selector = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &selector, 0, nil, &size) == noErr,
              size > 0, size % UInt32(MemoryLayout<AudioDeviceID>.size) == 0 else {
            devices = []; error = "출력 장치를 불러오지 못했습니다."; return
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let result = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &selector, 0, nil, &size, bytes.baseAddress!)
        }
        guard result == noErr else { devices = []; error = "출력 장치를 불러오지 못했습니다."; return }
        ids = Array(ids.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
        devices = ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var property = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &property, 0, nil, &nameSize, &name) == noErr,
                  let value = name?.takeRetainedValue() else { return nil }
            let clean = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : AudioOutputDevice(id: id, name: clean)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var currentProperty = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var currentID = AudioDeviceID(kAudioObjectUnknown)
        var idSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &currentProperty, 0, nil, &idSize, &currentID) == noErr { current = currentID }
        else { current = AudioDeviceID(kAudioObjectUnknown) }
        error = ""
    }

    func select(_ id: AudioDeviceID) {
        guard devices.contains(where: { $0.id == id }) else { error = "출력 장치가 더 이상 연결되어 있지 않습니다."; return }
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var selected = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &selected)
        guard status == noErr else { error = "오디오 출력을 변경하지 못했습니다."; return }
        refresh()
    }
}

struct AudioOutputMenu: View {
    @ObservedObject var model: AudioOutputModel
    var body: some View {
        Menu {
            if !model.error.isEmpty { Text(model.error) }
            else if model.devices.isEmpty { Text("사용 가능한 출력 장치 없음") }
            ForEach(model.devices) { device in
                Button(action: { model.select(device.id) }) {
                    if device.id == model.current { Label(device.name, systemImage: "checkmark") }
                    else { Text(device.name) }
                }
            }
            Divider()
            Button("출력 장치 새로고침") { model.refresh() }
        } label: {
            Image(systemName: "laptopcomputer").frame(width: 24, height: 24).background(.white.opacity(0.08), in: Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help(model.error.isEmpty ? "오디오 출력 장치 선택" : model.error)
        .accessibilityLabel("오디오 출력 장치 선택")
        .onAppear { model.refresh() }
    }
}
