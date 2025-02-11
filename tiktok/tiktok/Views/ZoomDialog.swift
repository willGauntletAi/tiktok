import SwiftUI

struct ZoomDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var startZoomIn: Double
    @State private var zoomInComplete: Double?
    @State private var startZoomOut: Double?
    @State private var zoomOutComplete: Double?
    let clipDuration: Double
    let existingConfig: ZoomConfig?
    let onSave: (ZoomConfig) -> Void

    init(clipDuration: Double, existingConfig: ZoomConfig? = nil, onSave: @escaping (ZoomConfig) -> Void) {
        self.clipDuration = clipDuration
        self.existingConfig = existingConfig
        self.onSave = onSave
        _startZoomIn = State(initialValue: existingConfig?.startZoomIn ?? 0)
        _zoomInComplete = State(initialValue: existingConfig?.zoomInComplete)
        _startZoomOut = State(initialValue: existingConfig?.startZoomOut)
        _zoomOutComplete = State(initialValue: existingConfig?.zoomOutComplete)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Zoom In")) {
                    HStack {
                        Text("Start")
                        Slider(value: $startZoomIn, in: 0 ... clipDuration) {
                            Text("Start Zoom In")
                        }
                        Text(String(format: "%.1fs", startZoomIn))
                    }

                    Toggle(isOn: Binding(
                        get: { zoomInComplete != nil },
                        set: { if !$0 { zoomInComplete = nil } else { zoomInComplete = startZoomIn + 1 } }
                    )) {
                        Text("Set Zoom In Complete")
                    }

                    if zoomInComplete != nil {
                        HStack {
                            Text("Complete")
                            Slider(
                                value: Binding(
                                    get: { zoomInComplete ?? startZoomIn },
                                    set: { zoomInComplete = $0 }
                                ),
                                in: startZoomIn ... clipDuration
                            )
                            Text(String(format: "%.1fs", zoomInComplete ?? 0))
                        }
                    }
                }

                Section(header: Text("Zoom Out")) {
                    Toggle(isOn: Binding(
                        get: { startZoomOut != nil },
                        set: { if !$0 {
                            startZoomOut = nil
                            zoomOutComplete = nil
                        } else {
                            startZoomOut = (zoomInComplete ?? startZoomIn) + 1
                        }}
                    )) {
                        Text("Add Zoom Out")
                    }

                    if startZoomOut != nil {
                        HStack {
                            Text("Start")
                            Slider(
                                value: Binding(
                                    get: { startZoomOut ?? (zoomInComplete ?? startZoomIn) + 1 },
                                    set: { startZoomOut = $0 }
                                ),
                                in: (zoomInComplete ?? startZoomIn) ... clipDuration
                            )
                            Text(String(format: "%.1fs", startZoomOut ?? 0))
                        }

                        Toggle(isOn: Binding(
                            get: { zoomOutComplete != nil },
                            set: { if !$0 { zoomOutComplete = nil } else { zoomOutComplete = startZoomOut! + 1 } }
                        )) {
                            Text("Set Zoom Out Complete")
                        }

                        if zoomOutComplete != nil {
                            HStack {
                                Text("Complete")
                                Slider(
                                    value: Binding(
                                        get: { zoomOutComplete ?? startZoomOut! },
                                        set: { zoomOutComplete = $0 }
                                    ),
                                    in: startZoomOut! ... clipDuration
                                )
                                Text(String(format: "%.1fs", zoomOutComplete ?? 0))
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingConfig == nil ? "Add Zoom" : "Edit Zoom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let config = ZoomConfig(
                            startZoomIn: startZoomIn,
                            zoomInComplete: zoomInComplete,
                            startZoomOut: startZoomOut,
                            zoomOutComplete: zoomOutComplete
                        )
                        onSave(config)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ZoomDialog(clipDuration: 10.0) { config in
        print("Zoom config saved: \(config)")
    }
}
