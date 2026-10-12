import SwiftUI

struct BerryControlsView: View {
    @ObservedObject var settings: BerrySettings
    @Environment(\.dismiss) private var dismiss
    @State private var showingBackgroundPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Lighting") {
                    valueSlider("Key light", value: $settings.keyIntensity, range: 0...12)
                    ColorPicker("Light color", selection: $settings.keyColor)
                    valueSlider("Light angle", value: $settings.keyAzimuth, range: -180...180)
                    valueSlider("Ambient light", value: $settings.ambientIntensity, range: 0...1)
                }
                Section("Cavity glow") {
                    valueSlider("Intensity", value: $settings.innerIntensity, range: 0...12)
                    ColorPicker("Glow color", selection: $settings.innerColor)
                    valueSlider("Wall thickness", value: $settings.innerWall, range: 0.2...1.2)
                }
                Section("Flesh") {
                    valueSlider("Translucency", value: $settings.beadGlow, range: 0...4)
                    valueSlider("Clarity", value: $settings.transDepth, range: 0.03...1)
                    valueSlider("Roughness", value: $settings.roughness, range: 0.3...2)
                    ColorPicker("Transmission color", selection: $settings.transColor)
                }
                Section("Depth of field") {
                    Toggle("Depth of field", isOn: $settings.depthOfField)
                        .accessibilityIdentifier("depth-of-field-toggle")
                    valueSlider("Focus offset", value: $settings.focusOffset, range: -3...3)
                    valueSlider("Focus range", value: $settings.focusRange, range: 0.1...8)
                    valueSlider("Blur amount", value: $settings.blurAmount, range: 0...10)
                }

            }
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Background") { showingBackgroundPicker = true }
                        Toggle("Fuzz", isOn: $settings.fuzzVisible)
                        Toggle("Auto spin", isOn: $settings.spinning)
                        Toggle("Gyroscope", isOn: $settings.gyroscopeEnabled)
                            .accessibilityIdentifier("gyroscope-toggle")
                        Toggle("Fast rendering", isOn: $settings.fastRendering)
                            .accessibilityIdentifier("fast-rendering-toggle")
                        Button("Reset camera") { settings.resetCamera = UUID() }
                    } label: {
                        Label("View", systemImage: "eye")
                    }
                    .accessibilityIdentifier("view-menu")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingBackgroundPicker) {
            NavigationStack {
                Form {
                    ColorPicker("Background", selection: $settings.backgroundColor)
                }
                .navigationTitle("Background")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingBackgroundPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .preferredColorScheme(.dark)
    }

    private func valueSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 4)
    }
}

struct NativeBerryView: View {
    @StateObject private var settings = BerrySettings()
    @State private var showingAdjustments = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            settings.backgroundColor.ignoresSafeArea()
            BerryMetalView(settings: settings, paused: scenePhase != .active)
                .ignoresSafeArea()
                .accessibilityLabel("3D raspberry. Tilt or turn your device to rotate with Gyroscope enabled in Adjust. Drag with one finger to rotate, two fingers to pan, pinch to zoom, double tap to reset.")
            if let error = settings.renderError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Unable to render raspberry").font(.headline)
                    Text(error).font(.caption).multilineTextAlignment(.center)
                }
                .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(24)
                .accessibilityIdentifier("renderer-error")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                controls(showLabels: true)
                controls(showLabels: false)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingAdjustments) {
            BerryControlsView(settings: settings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private func controls(showLabels: Bool) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(BerryPreset.allCases) { preset in
                    Button {
                        settings.reelPlaying = false
                        settings.select(preset)
                    } label: {
                        if settings.preset == preset {
                            Label(preset.rawValue, systemImage: "checkmark")
                        } else {
                            Text(preset.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(settings.reelPlaying ? (settings.reelShotName ?? settings.preset.rawValue) : settings.preset.rawValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .contentShape(Rectangle())
                .frame(maxWidth: showLabels ? nil : 120)
            }
            .accessibilityIdentifier("preset-menu")
            .accessibilityLabel("Lighting preset, \(settings.reelPlaying ? (settings.reelShotName ?? settings.preset.rawValue) : settings.preset.rawValue)")

            Button {
                settings.reelPlaying.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: settings.reelPlaying ? "stop.fill" : "play.fill")
                    if showLabels { Text(settings.reelPlaying ? "Stop" : "Reel") }
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("reel-button")
            .accessibilityLabel(settings.reelPlaying ? "Stop reel" : "Play reel")

            Button { showingAdjustments = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    if showLabels { Text("Adjust") }
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("adjust-button")
            .accessibilityLabel("Adjust")

        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .padding(4)
        .background {
            Capsule().fill(.ultraThinMaterial).opacity(0.6)
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}
