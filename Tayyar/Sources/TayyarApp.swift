import SwiftUI

@main
struct TayyarApp: App {
    @State private var engine: SensorEngine = {
        let e = SensorEngine()
        #if DEBUG
        // Simulator-only screenshot fixture: the simulator has no magnetometer.
        if let v = UserDefaults.standard.string(forKey: "demoScore"), let d = Double(v) {
            e.available = true; e.baselineMagnitude = 45; e.humMeasurable = true
            e.humScore = d; e.magScore = d * 0.7; e.magDeviation = d * 40; e.humRatio = 1 + d * 3
            e.humLikely = d > 0.6; e.metalLikely = d > 0.4
            e.rawMagnitude = 372.4; e.fieldMagnitude = 45 + d * 40; e.filteredMagnitude = 45 + d * 40; e.hardIronMagnitude = 341
            e.phaseName = "ready"; e.rawRate = 100; e.hfVariance = 4 + d * 20; e.calibrationAccuracy = "عالية"
        }
        #endif
        return e
    }()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .dynamicTypeSize(.xLarge ... .accessibility3)
        }
    }
}

/// Direction A — "instrument": near-black surfaces, one amber accent, monospaced readouts.
/// Contrast (on bg): text 17:1, secondary 5.9:1, amber 10:1. Status never relies on colour alone.
enum Theme {
    static let bg = Color(red: 0.043, green: 0.043, blue: 0.051)        // #0B0B0D
    static let surface = Color(red: 0.090, green: 0.094, blue: 0.106)   // #17181B
    static let surface2 = Color(red: 0.114, green: 0.118, blue: 0.133)  // #1D1E22
    static let stroke = Color(red: 0.149, green: 0.153, blue: 0.169)    // #26272B
    static let card = surface
    static let amber = Color(red: 1.0, green: 0.690, blue: 0.125)       // #FFB020
    static let text = Color(red: 0.949, green: 0.937, blue: 0.910)      // #F2EFE8
    static let secondary = Color(red: 0.62, green: 0.615, blue: 0.60)
    static let ok = Color(red: 0.204, green: 0.827, blue: 0.600)        // #34D399
    static let danger = Color(red: 1.0, green: 0.353, blue: 0.353)      // #FF5A5A
    static func level(_ s: Double) -> Color { s < 0.33 ? ok : (s < 0.66 ? amber : danger) }
    static func mono(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font { .system(size: size, weight: w, design: .monospaced) }
    enum R { static let s: CGFloat = 12, m: CGFloat = 16, l: CGFloat = 22 }
}

/// Instrument card: surface + hairline stroke.
struct Panel<C: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: C
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.R.m))
            .overlay(RoundedRectangle(cornerRadius: Theme.R.m).stroke(Theme.stroke, lineWidth: 1))
    }
}

/// Primary amber pill (black label, 10:1 contrast) with pressed feedback.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.amber
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.title3.bold()).foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(tint.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: Theme.R.m))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.surface2.opacity(configuration.isPressed ? 0.6 : 1), in: .rect(cornerRadius: Theme.R.m))
            .overlay(RoundedRectangle(cornerRadius: Theme.R.m).stroke(Theme.stroke, lineWidth: 1))
    }
}

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    var body: some View {
        #if DEBUG
        if let d = UserDefaults.standard.string(forKey: "demoScreen") {
            switch d {
            case "finder": NavigationStack { SensorFinderView() }
            case "map": NavigationStack { WallMapView() }
            case "guide": NavigationStack { CalibrationGuideView() }
            default: TestModeView()
            }
        } else { main }
        #else
        main
        #endif
    }
    @ViewBuilder private var main: some View {
        if onboarded {
            TabView {
                ScanView().tabItem { Label("الفحص", systemImage: "bolt.horizontal.circle") }
                TestModeView().tabItem { Label("وضع التجربة", systemImage: "waveform.path.ecg") }
                SettingsView().tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }
            }
        } else {
            OnboardingView { onboarded = true }
        }
    }
}
