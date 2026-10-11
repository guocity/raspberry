import SwiftUI

public struct BerryControlsView: View {
    @ObservedObject public var settings: BerrySettings

    public init(settings: BerrySettings) {
        self.settings = settings
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Lighting") {
                    Slider(value: $settings.keyIntensity, in: 0...12) {
                        Text("Key Intensity: \(settings.keyIntensity, specifier: "%.1f")")
                    }
                    ColorPicker("Key Light Color", selection: $settings.keyColor)
                    Slider(value: $settings.keyAzimuth, in: -180...180) {
                        Text("Azimuth: \(settings.keyAzimuth, specifier: "%.0f")°")
                    }
                }

                Section("Inner Cavity Lamp (Lantern Glow)") {
                    Slider(value: $settings.innerIntensity, in: 0...20) {
                        Text("Intensity: \(settings.innerIntensity, specifier: "%.1f")")
                    }
                    ColorPicker("Cavity Color", selection: $settings.innerColor)
                    Slider(value: $settings.innerWall, in: 0.2...1.2) {
                        Text("Wall Thickness: \(settings.innerWall, specifier: "%.2f") cm")
                    }
                }

                Section("Translucency & Flesh") {
                    Slider(value: $settings.beadGlow, in: 0...4) {
                        Text("Bead Translucency: \(settings.beadGlow, specifier: "%.2f")")
                    }
                    ColorPicker("Flesh Color", selection: $settings.transColor)
                    Slider(value: $settings.transDepth, in: 0.03...1.0) {
                        Text("Clarity: \(settings.transDepth, specifier: "%.2f") cm")
                    }
                }

                Section("Fuzz / Hair") {
                    Toggle("Show Fuzz", isOn: $settings.fuzzVisible)
                    Slider(value: $settings.backlightHalo, in: 0...6) {
                        Text("Backlight Halo: \(settings.backlightHalo, specifier: "%.1f")")
                    }
                }
            }
            .navigationTitle("Raspberry Controls")
        }
    }
}
