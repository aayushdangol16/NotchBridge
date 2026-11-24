import AudioToolbox
import CoreAudio
import Foundation

/// Output volume / mute of the current default output device, via CoreAudio property listeners
/// (no permissions, no polling). Follows default-device changes (AirPods connecting, etc.).
final class VolumeMonitor {
    /// Main thread: level 0…100, muted.
    var onChange: (Int, Bool) -> Void = { _, _ in }

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var last: (Int, Bool)?
    private var started = false
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read(notify: true) }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.bindDefaultDevice() }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard !started else { return }
        started = true
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, deviceListener)
        bindDefaultDevice()
    }

    func stop() {
        guard started else { return }
        started = false
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, .main, deviceListener)
        unbind()
    }

    private func bindDefaultDevice() {
        unbind()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultDeviceAddress, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return }
        device = id
        if AudioObjectHasProperty(id, &Self.volumeAddress) {
            AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, .main, listener)
        }
        if AudioObjectHasProperty(id, &Self.muteAddress) {
            AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, listener)
        }
        read(notify: false)   // new device: remember its level without popping
    }

    private func unbind() {
        guard device != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(device, &Self.volumeAddress, .main, listener)
        AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, listener)
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func read(notify: Bool) {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &Self.volumeAddress, 0, nil, &size, &volume) == noErr else { return }
        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &muted)
        let now = (Int((volume * 100).rounded()), muted != 0)
        defer { last = now }
        guard notify, let last, last != now else { return }
        onChange(now.0, now.1)
    }
}
