import SwiftUI

/// Wall map: the user sweeps the wall cell by cell and taps a cell to store the current
/// magnetic deviation there. Produces a heat-map of the wall (on device only).
struct WallMapView: View {
    @Environment(SensorEngine.self) private var engine
    static let cols = 6, rows = 8
    @State private var cells: [Int: Double] = WallMapView.loadCells()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("قسّم الجدار في بالك لمربعات. حط ظهر الجوال على كل مكان واضغط المربع المقابل له عشان تحفظ القراءة. المربعات الحمرا فيها تغيّر مغناطيسي أعلى")
                    .font(.callout).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Panel(padding: 12) {
                    HStack {
                        Text("القراءة الحالية").font(.subheadline).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(String(format: "%.0f µT", engine.magDeviation)).font(Theme.mono(20)).foregroundStyle(Theme.level(engine.magScore))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<Self.rows, id: \.self) { r in
                        GridRow {
                            ForEach(0..<Self.cols, id: \.self) { c in
                                let i = r * Self.cols + c
                                let v = cells[i]
                                Button { cells[i] = engine.magScore; Self.save(cells) } label: {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(v.map { Theme.level($0).opacity(0.35 + 0.65 * $0) } ?? Theme.surface2)
                                        .overlay(Text(v.map { "\(Int($0 * 100))" } ?? "").font(.caption2.monospaced()).foregroundStyle(.black))
                                        .aspectRatio(1, contentMode: .fit)
                                }
                                .accessibilityLabel("مربع \(i + 1)" + (v.map { "، قراءة \(Int($0 * 100))" } ?? "، فاضي"))
                            }
                        }
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
                Text("الخريطة تبين أماكن الحديد والمعدن تقريبياً وما تضمن إن المكان خالي. افصل الكهربا دايماً قبل الخرم")
                    .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .background(Theme.bg)
        .navigationTitle("خريطة الجدار")
        .toolbar { if !cells.isEmpty { Button("امسح") { cells = [:]; Self.save(cells) } } }
        .onAppear { engine.start() }
    }

    static func loadCells() -> [Int: Double] {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "demoScreen") == "map" {
            var m: [Int: Double] = [:]
            for i in 0..<(rows * cols) { let c = Double(i % cols), r = Double(i / cols)
                m[i] = max(0.03, min(1, 1 - abs(c - 3.6) / 2.2) * (0.6 + 0.4 * sin(r))) }
            return m
        }
        #endif
        guard let d = UserDefaults.standard.data(forKey: "wallMap"),
              let m = try? JSONDecoder().decode([Int: Double].self, from: d) else { return [:] }
        return m
    }
    static func save(_ m: [Int: Double]) { UserDefaults.standard.set(try? JSONEncoder().encode(m), forKey: "wallMap") }
}

/// Step-by-step calibration guide.
struct CalibrationGuideView: View {
    private let steps: [(String, String)] = [
        ("hand.raised", "شيل الجوال من الجراب لو فيه مغناطيس أو حديد، وبعّد الساعة والمفاتيح"),
        ("figure.walk", "ابعد متر تقريباً عن الجدران والأجهزة والطاولات الحديد"),
        ("infinity", "لو دقة البوصلة منخفضة حرّك الجوال في الهوا على شكل رقم ٨ كم مرة"),
        ("scope", "اضغط «ابدأ المعايرة» وخل الجوال ثابت لين توصل ١٠٠٪"),
        ("rectangle.portrait.and.arrow.right", "حط ظهر الجوال مسطّح على الجدار وحركه ببطء أفقي ثم عمودي"),
        ("arrow.clockwise", "لو تغيّرت الغرفة أو القراءة صارت غريبة، أعد المعايرة")
    ]
    var body: some View {
        List {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                Label { Text("\(i + 1). \(s.1)") } icon: { Image(systemName: s.0).foregroundStyle(Theme.amber) }
            }
            Section { Text("تيّار يقيس المجال المغناطيسي بس. تقدير مساعد وليس جهاز سلامة") .foregroundStyle(.secondary) }
        }
        .navigationTitle("دليل المعايرة")
    }
}
