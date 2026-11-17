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
    @AppStorage("showGameMenu") private var showGameMenu = true
    @AppStorage("screenLayout") private var screenLayout = ScreenLayout.initialValue
    @State private var swapped = false
    @State private var showingEmulatedDevices = false
    @State private var showPauseButton = false
    @State private var pauseButtonHideGeneration = 0
    @State private var pausedByOurButton = false
    @State private var pausedByBackground = false
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
            // A small reveal target avoids stealing touches from the Wii U screen.
            VStack(spacing: 8) {
                if showPauseButton {
                    Button {
                        togglePause()
                    } label: {
                        Image(systemName: pausedByOurButton ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.65), in: Circle())
                    }
                    .accessibilityLabel(pausedByOurButton ? "Resume game" : "Pause game")
                }
                Button {
                    showPauseButton = true
                    scheduleHidePauseButton()
                } label: {
                    // Keep the tap target, but do not cover the game with a
                    // permanently visible ellipsis.
                    Color.clear.frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Show game controls")
            }
            .padding(12)
        }
        .overlay(alignment: .top) {
            if showGameMenu {
                Menu {
                    if screenLayout == .singleScreen && !air.connected {
                        Button {
                            swapped.toggle()
                        } label: {
                            Label("Swap TV and GamePad", systemImage: "rectangle.2.swap")
                        }
                    }
                    Button {
                        showPauseButton = true
                        scheduleHidePauseButton()
                    } label: {
                        Label("Show Pause Control", systemImage: "pause.circle")
                    }
                    if configManager.emulateSkylanderPortal.wrappedValue ||
                       configManager.emulateInfinityBase.wrappedValue ||
                       configManager.emulateDimensionsToypad.wrappedValue {
                        Button {
                            showingEmulatedDevices = true
                        } label: {
                            Label("Emulated Devices", systemImage: "externaldrive.connected.to.line.below")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 30)
                        .background(.black.opacity(0.4), in: Capsule())
                }
                .accessibilityLabel("Game menu")
                .padding(10)
            }
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
            CemuSetEmulationPaused(scenePhase != .active)
            pausedByBackground = scenePhase != .active
            updateVisibleOutputs()
            Air.play(AnyView(MetalViewContainer(metalView: cemuView)))
        }
        .onChange(of: swapped) { _ in updateVisibleOutputs() }
        .onChange(of: screenLayout) { _ in updateVisibleOutputs() }
        .onChange(of: air.connected) { _ in updateVisibleOutputs() }
        .onChange(of: scenePhase) { phase in
            // Background audio must stop independently of the game's START key.
            // Do not toggle START here: that may open a menu or resume the game.
            if phase == .active {
                // Preserve a user-requested pause when returning to the app.
                pausedByBackground = false
                CemuSetEmulationPaused(pausedByOurButton)
            } else {
                pausedByBackground = true
                CemuSetEmulationPaused(true)
                showPauseButton = false
                pauseButtonHideGeneration += 1
            }
        }
        .onDisappear {
            Air.stop()
            CemuUIKit_SetVisibleOutputs(false, false)
        }
    }
    
    private func togglePause() {
        // Pause Cemu's PPC scheduler, not a virtual controller. This works
        // regardless of whether a Joy-Con replaced the on-screen controls.
        pausedByOurButton.toggle()
        CemuSetEmulationPaused(pausedByOurButton || pausedByBackground)
        if !pausedByOurButton { scheduleHidePauseButton() }
    }

    private func scheduleHidePauseButton() {
        pauseButtonHideGeneration += 1
        let generation = pauseButtonHideGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard pauseButtonHideGeneration == generation, !pausedByOurButton else { return }
            showPauseButton = false
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
