//
//  EmulationView.swift
//  MeloCafe
//
//  Created by Stossy11 on 9/4/2026.
//

import SwiftUI
import Melo_Controller

struct EmulationView: View {
    let cemuView: MetalView
    let cemuPadView: MetalView
    @StateObject private var controllerManager = ControllerManager.shared
    @StateObject private var controllerHandler = VirtualControllerHandler()
    @AppStorage("showSwapButton") private var showSwapButton = true
    @AppStorage("screenLayout") private var screenLayout = ScreenLayout.initialValue
    @State private var swapped = false
    @State private var showingEmulatedDevices = false
    @State private var showPauseControl = false
    @State private var pauseControlGeneration = 0
    @State private var pausedByOverlay = false
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var air = Air.shared
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    private var visibleScreens: [Bool] {
        if air.connected { return [false] }
        if screenLayout.showsBothScreens { return swapped ? [false, true] : [true, false] }
        return [!swapped]
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geometry in
                let portrait = geometry.size.height >= geometry.size.width
                if screenLayout == .smallGamePadTopRight && !air.connected {
                    let padWidth = geometry.size.width * 0.25
                    let padHeight = min(padWidth * 9 / 16, geometry.size.height)
                    HStack(alignment: .top, spacing: 0) {
                        MetalViewContainer(metalView: cemuView)
                            .frame(width: geometry.size.width - padWidth,
                                   height: geometry.size.height)
                        MetalViewContainer(metalView: cemuPadView)
                            .frame(width: padWidth, height: padHeight)
                    }
                } else if portrait {
                    VStack(spacing: 0) { screens }
                } else {
                    HStack(spacing: 0) { screens }
                }
            }
            .ignoresSafeArea(.all, edges: verticalSizeClass == .regular ? .horizontal : .all)
            
            if controllerManager.hasVirtual() {
                ControllerView(controller: controllerHandler, isEditing: false)
            }
        }
        .overlay(alignment: .topLeading) {
            if showSwapButton && screenLayout == .singleScreen && !air.connected {
                Button {
                    swapped.toggle()
                } label: {
                    ButtonView(controller: controllerHandler, disabled: true, button: .swap, opacity: 0.8)
                }
                .accessibilityLabel("Swap TV and GamePad") // i'm not sure who would need this because you would need to be able to see the screen itself but might as well -stossy11
                .padding(10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                if showPauseControl {
                    Button {
                        toggleGamePause()
                    } label: {
                        Image(systemName: pausedByOverlay ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.65), in: Circle())
                    }
                    .accessibilityLabel(pausedByOverlay ? "Resume game (START)" : "Pause game (START)")
                }
                Button {
                    showPauseControl = true
                    schedulePauseControlHide()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 28)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                .accessibilityLabel("Show pause control")
            }
            .padding(12)
        }
        .statusBarHidden(true)
        .overlay(alignment: .topTrailing) {
            if configManager.emulateSkylanderPortal.wrappedValue ||
                configManager.emulateInfinityBase.wrappedValue ||
                configManager.emulateDimensionsToypad.wrappedValue {
                Button {
                    showingEmulatedDevices = true
                } label: {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.6), in: Circle())
                }
                .accessibilityLabel("Emulated Devices")
                .sheet(isPresented: $showingEmulatedDevices) {
                    EmulatedDevicesView()
                }
                .padding(10)
            }
        }
        .onAppear {
            updateVisibleOutputs()
            Air.play(AnyView(MetalViewContainer(metalView: cemuView)))
        }
        .onChange(of: swapped) { _ in updateVisibleOutputs() }
        .onChange(of: screenLayout) { _ in updateVisibleOutputs() }
        .onChange(of: air.connected) { _ in updateVisibleOutputs() }
        .onChange(of: scenePhase) { phase in
            if phase == .inactive && !pausedByOverlay && controllerManager.virtualController.attached {
                sendStartPulse()
                pausedByOverlay = true
                showPauseControl = true
            }
        }
        .onDisappear {
            Air.stop()
            CemuUIKit_SetVisibleOutputs(false, false)
        }
    }
    
    private func sendStartPulse() {
        let controller = controllerManager.virtualController
        guard controller.attached else { return }
        controller.pressButton(.start)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            controller.releaseButton(.start)
        }
    }

    private func toggleGamePause() {
        guard controllerManager.virtualController.attached else { return }
        sendStartPulse()
        pausedByOverlay.toggle()
        if !pausedByOverlay { schedulePauseControlHide() }
    }

    private func schedulePauseControlHide() {
        pauseControlGeneration += 1
        let generation = pauseControlGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard pauseControlGeneration == generation, !pausedByOverlay else { return }
            showPauseControl = false
        }
    }

    private var screens: some View {
        ForEach(visibleScreens, id: \.self) { main in
            MetalViewContainer(metalView: main ? cemuView : cemuPadView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func updateVisibleOutputs() {
        let both = air.connected || screenLayout.showsBothScreens
        
        CemuUIKit_SetVisibleOutputs(both || !swapped, both || swapped)
        
        if !both && !swapped { cemuPadView.cancelActiveTouches() }
    }
}

extension VirtualControllerButton {
    static var swap = Self("swap", systemName: "rectangle.2.swap", small: true)
}
