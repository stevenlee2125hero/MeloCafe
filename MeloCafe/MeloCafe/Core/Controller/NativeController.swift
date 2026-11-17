//
//  NativeController.swift
//  MeloCafe
//
//  Created by Stossy11 on 9/3/2026.
//

import Foundation
import GameController
import CoreHaptics
import UIKit

final class NativeController {
    let gc: GCController
    private(set) var coreHandle: UnsafeMutableRawPointer?
    nonisolated private let rumbleOutput: RumbleOutput
    nonisolated(unsafe) private var attachmentGeneration: UInt64 = 0
    
    nonisolated private let stateLock = NSLock()
    nonisolated private let motionLock = NSLock()
    nonisolated(unsafe) private var _state  = GCBridgeControllerState()
    nonisolated(unsafe) private var _motion = GCBridgeMotionState()
    
    public var controllerType: ControllerType = .Pro
    
    init(gc: GCController) {
        self.gc = gc
        rumbleOutput = RumbleOutput(gc: gc)
        gc.handlerQueue = .main

    }
    
    deinit {
        detach()
    }
    
    public func detach() {
        gc.extendedGamepad?.valueChangedHandler = nil
        gc.motion?.valueChangedHandler = nil
        
        if let motion = gc.motion, motion.sensorsRequireManualActivation {
            motion.sensorsActive = false
        }
        
        stateLock.lock()
        
        attachmentGeneration &+= 1
        _state = GCBridgeControllerState()
        
        stateLock.unlock()
        
        
        motionLock.lock()
        _motion = GCBridgeMotionState()
        motionLock.unlock()
        
        
        let handle = coreHandle
        coreHandle = nil
        if let handle { GCControllerBridge_remove(handle) }
        
        rumbleOutput.detach()
    }
    
    public func registerWithCore(_ controllerType: ControllerType) {
        guard controllerType != .MAX else { return }
        self.controllerType = controllerType
        if let handle = coreHandle {
            GCControllerBridge_configure(handle, controllerType.rawValue)
            return
        }
        
        detach()
        if let pad = gc.extendedGamepad { updateState(from: pad) }
        
        let ctx = Unmanaged.passRetained(self).toOpaque()
        
        var desc = GCBridgeControllerDesc()
        desc.context = ctx
        
        self.controllerType = controllerType
        desc.controllerType = controllerType.rawValue
        
        desc.poll_state = { ctx in
            let me = Unmanaged<NativeController>.fromOpaque(ctx!).takeUnretainedValue()
            me.stateLock.lock()
            defer { me.stateLock.unlock() }
            return me._state
        }
        
        if gc.motion?.hasRotationRate == true {
            desc.poll_motion = { ctx in NativeController.pollMotion(ctx) }
        }
        rumbleOutput.attach(active: UIApplication.shared.applicationState == .active)
        desc.rumble = { ctx, start in NativeController.rumble(ctx, start) }
        
        desc.release = { ctx in
            Unmanaged<NativeController>.fromOpaque(ctx!).release()
        }
        
        let name = gc.vendorName ?? "MFi Controller"
        name.withCString { ptr in
            desc.display_name = ptr
            coreHandle = GCControllerBridge_add(&desc)
        }
        
        if coreHandle == nil {
            Unmanaged<NativeController>.fromOpaque(ctx).release()
            return
        }
        
        let generation = attachmentGeneration
        gc.extendedGamepad?.valueChangedHandler = { [weak self] pad, _ in
            guard let self, self.coreHandle != nil,
                  self.attachmentGeneration == generation else { return }
            self.updateState(from: pad)
        }
        
        if let motion = gc.motion, motion.hasRotationRate {
            motion.valueChangedHandler = { [weak self] m in
                guard let self, self.coreHandle != nil,
                      self.attachmentGeneration == generation else { return }
                self.updateMotion(from: m)
            }
            
            if motion.sensorsRequireManualActivation {
                motion.sensorsActive = true
            }
        }
    }
    
    private nonisolated static func pollMotion(_ ctx: UnsafeMutableRawPointer?) -> GCBridgeMotionState {
        let me = Unmanaged<NativeController>.fromOpaque(ctx!).takeUnretainedValue()
        
        me.motionLock.lock()
        defer { me.motionLock.unlock() }
        
        return me._motion
    }
    
    private nonisolated static func rumble(
        _ ctx: UnsafeMutableRawPointer?,
        _ start: Bool
    ) {
        let me = Unmanaged<NativeController>.fromOpaque(ctx!).takeUnretainedValue()
        
        me.rumbleOutput.set(start)
    }
    
    private func updateState(from pad: GCExtendedGamepad) {
        var s = GCBridgeControllerState()
        
        func bit(_ pressed: Bool, _ bit: Int) { if pressed { s.buttons |= 1 << bit } }
        bit(pad.buttonA.isPressed, 0)
        bit(pad.buttonB.isPressed, 1)
        bit(pad.buttonX.isPressed, 2)
        bit(pad.buttonY.isPressed, 3)
        bit(pad.leftShoulder.isPressed, 4)
        bit(pad.rightShoulder.isPressed, 5)
        bit(pad.leftTrigger.isPressed, 6)
        bit(pad.rightTrigger.isPressed, 7)
        bit(pad.buttonOptions?.isPressed ?? false, 8)
        bit(pad.buttonMenu.isPressed, 9)
        bit(pad.leftThumbstickButton?.isPressed  ?? false, 10)
        bit(pad.rightThumbstickButton?.isPressed ?? false, 11)
        bit(pad.dpad.up.isPressed,    16)
        bit(pad.dpad.down.isPressed,  17)
        bit(pad.dpad.left.isPressed,  18)
        bit(pad.dpad.right.isPressed, 19)
        
        s.leftStick = GCBridgeVec2(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
        
        s.rightStick = GCBridgeVec2(x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
        s.leftTrigger = pad.leftTrigger.value
        s.rightTrigger = pad.rightTrigger.value
        
        stateLock.lock()
        _state = s
        stateLock.unlock()
    }
    
    private func updateMotion(from m: GCMotion) {
        var mo = GCBridgeMotionState()
        
        let a = SIMD3<Float>(
            Float(m.acceleration.x),
            -Float(m.acceleration.y),
            -Float(m.acceleration.z)
        )
        
        let g = SIMD3<Float>(
            Float(m.rotationRate.x),
            -Float(m.rotationRate.z),
            Float(m.rotationRate.y)
        )
        
        mo.accelerometer = GCBridgeVec3(x: a.x, y: a.y, z: a.z)
        mo.gyroscope = GCBridgeVec3(x: g.x, y: g.y, z: g.z)
        
        mo.orientation = GCBridgeVec3(x: 0, y: 0, z: 0)
        mo.quaternion  = GCBridgeQuat(w: 1, x: 0, y: 0, z: 0)
        
        mo.timestamp = ProcessInfo.processInfo.systemUptime
        
        motionLock.lock()
        _motion = mo
        motionLock.unlock()
    }
    
}

// All engine/player state belongs to this serial queue. Core callbacks only enqueue.
private final class RumbleOutput: @unchecked Sendable {
    nonisolated private let queue = DispatchQueue(label: "MeloCafe.rumble", qos: .userInitiated)
    nonisolated private let gc: GCController
    nonisolated(unsafe) private var attached = false
    nonisolated(unsafe) private var active = false
    nonisolated(unsafe) private var requested = false
    nonisolated(unsafe) private var engines: [CHHapticEngine?] = [nil, nil]
    nonisolated(unsafe) private var players: [CHHapticAdvancedPatternPlayer?] = [nil, nil]
    nonisolated(unsafe) private var failed = [false, false]
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    nonisolated init(gc: GCController) {
        self.gc = gc
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.suspend() })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.async { [weak self] in self?.active = true }
        })
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    nonisolated func attach(active isActive: Bool) {
        queue.async { [self] in attached = true; active = isActive; failed = [false, false] }
    }

    nonisolated func detach() {
        queue.async { [self] in
            attached = false
            requested = false
            stopAndReleaseEngines()
        }
    }

    nonisolated func suspend() {
        queue.async { [self] in
            active = false
            requested = false
            stopAndReleaseEngines()
        }
    }

    nonisolated func set(_ start: Bool) {
        queue.async { [self] in
            guard attached else { return }
            guard start else { requested = false; stop(); return }
            guard active, !requested else { return }
            requested = true
            // Failures are isolated by output; no retry loop on the emulator thread.
            for index in 0..<2 where !failed[index] {
                do {
                    if engines[index] == nil {
                        if index == 0 {
                            if let haptics = gc.haptics {
                                engines[index] = haptics.createEngine(withLocality: .all)
                                    ?? haptics.createEngine(withLocality: .default)
                            }
                        } else if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
                            engines[index] = try CHHapticEngine()
                            engines[index]?.playsHapticsOnly = true
                        }
                        guard let engine = engines[index] else {
                            failed[index] = true
                            NSLog("Rumble output %d unavailable", index)
                            continue
                        }
                        engine.resetHandler = { [weak self, weak engine] in
                            guard let engine else { return }
                            self?.invalidate(index, engine: engine)
                        }
                        engine.stoppedHandler = { [weak self, weak engine] _ in
                            guard let engine else { return }
                            self?.invalidate(index, engine: engine)
                        }
                    }
                    guard let engine = engines[index] else { continue }
                    try engine.start()
                    let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ], relativeTime: 0, duration: 1)
                    let pattern = try CHHapticPattern(events: [event], parameters: [])
                    let player = try engine.makeAdvancedPlayer(with: pattern)
                    player.loopEnabled = true
                    players[index] = player
                    try player.start(atTime: CHHapticTimeImmediate)
                } catch {
                    failed[index] = true
                    NSLog("Rumble output %d start failed: %@", index, String(describing: error))
                    stop(index)
                }
            }
        }
    }

    nonisolated private func invalidate(_ index: Int, engine: CHHapticEngine) {
        queue.async { [self] in
            guard engines[index] === engine else { return }
            // Never replay an old rumble after an interruption/reset.
            stop(index)
            engines[index] = nil
            failed[index] = true
        }
    }

    // Tear down both output engines on disconnect/background. Invalidate identity
    // before stopping so delayed stoppedHandler callbacks cannot affect a new engine.
    nonisolated private func stopAndReleaseEngines() {
        stop()
        for index in 0..<2 {
            let engine = engines[index]
            engines[index] = nil
            engine?.resetHandler = {}
            engine?.stoppedHandler = { _ in }
            engine?.stop(completionHandler: nil)
        }
    }

    nonisolated private func stop() { for index in 0..<2 { stop(index) } }

    nonisolated private func stop(_ index: Int) {
        do { try players[index]?.stop(atTime: CHHapticTimeImmediate) }
        catch {
            NSLog("Rumble output %d stop failed: %@", index, String(describing: error))
            engines[index]?.stop(completionHandler: nil)
            failed[index] = true
        }
        players[index] = nil
    }
}
