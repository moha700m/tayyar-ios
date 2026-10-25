import SwiftUI

struct HistoryView: View {
    @State private var items = ScanHistory.load()
    var body: some View {
        List {
            if items.isEmpty {
                Text("ما فيه نتائج للحين. لما تيّار يلقط إشارة وقت الفحص تنحفظ هنا على جوالك بس").foregroundStyle(.secondary)
            }
            ForEach(items) { r in
                HStack {
                    Image(systemName: r.kind == "wire" ? "bolt.fill" : "square.grid.3x3.fill").foregroundStyle(r.kind == "wire" ? .red : Theme.amber)
                    VStack(alignment: .leading) {
                        Text(r.kind == "wire" ? "إشارة سلك عليه حمل" : "حديد أو معدن").font(.headline)
                        Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(r.peak)").font(.title3.bold()).monospacedDigit()
                }
            }
        }
        .navigationTitle("سجل الفحص")
        .toolbar { if !items.isEmpty { Button("امسح") { ScanHistory.clear(); items = [] } } }
    }
}

/// Bubble level from deviceMotion gravity — handy when marking/hanging after a scan.
struct LevelView: View {
    @Environment(SensorEngine.self) private var engine
    var body: some View {
        let g = engine.gravity
        let roll = atan2(g.x, -g.z) * 180 / .pi, pitch = atan2(g.y, -g.z) * 180 / .pi
        let flatOK = abs(roll) < 1 && abs(pitch) < 1
        VStack(spacing: 24) {
            ZStack {
                Circle().stroke(.white.opacity(0.3), lineWidth: 3).frame(width: 260)
                Circle().stroke(.white.opacity(0.3), lineWidth: 1).frame(width: 50)
                Circle().fill(flatOK ? .green : Theme.amber).frame(width: 44)
                    .offset(x: CGFloat(max(-110, min(110, -roll * 6))), y: CGFloat(max(-110, min(110, pitch * 6))))
                    .animation(.linear(duration: 0.05), value: roll)
            }
            .environment(\.layoutDirection, .leftToRight)
            Text(String(format: "%.1f° / %.1f°", roll, pitch)).font(.largeTitle.bold()).monospacedDigit()
            Text(flatOK ? "مستوي ✓" : "حط الجوال على السطح وعدّل لين تصير الفقاعة في النص").font(.title3).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
        .navigationTitle("ميزان الاستواء")
        .onAppear { engine.start() }
        .accessibilityElement(children: .combine)
    }
}

struct ExplainView: View {
    var body: some View {
        List {
            Section("مؤشر الحديد والمعدن") {
                Text("الحديد والمسامير والمواسير الحديد تغيّر المجال المغناطيسي حول الجوال. تيّار يقارن القراءة بالمعايرة، فلو زادت أو نقصت بوضوح يرتفع المؤشر. النحاس والألمنيوم غالباً ما يبانون لأنهم ما يتأثرون بالمغناطيس")
            }
            Section("مؤشر سلك الكهربا") {
                Text("السلك اللي يمشي فيه تيار متردد يطلع مجال يتذبذب ٦٠ مرة بالثانية. تيّار يدوّر على هالذبذبة بالذات. لو ما فيه جهاز شغال على السلك ما يطلع مجال وما يبان، عشان كذا شغّل جهاز يسحب كهربا قبل الفحص")
            }
            Section("حدود مهمة") {
                Text("تقدير مساعد وليس جهاز سلامة، وممكن يفوّت أسلاك. افصل الكهربا من الطبلون واستخدم جهاز كشف احترافي قبل الخرم")
            }
        }
        .navigationTitle("الفرق بين الحديد والسلك")
    }
}

enum ResultCard {
    @MainActor static func render(peak: Double) -> Image {
        let v = VStack(spacing: 14) {
            Text("تيّار").font(.system(size: 44, weight: .bold))
            Text("\(Int(peak * 100))").font(.system(size: 90, weight: .bold, design: .rounded)).foregroundStyle(Theme.level(peak))
            Text(ScanStatus(score: peak).title).font(.title.bold())
            Text("أعلى قراءة في الفحص. تقدير مساعد وليس جهاز سلامة").font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40).frame(width: 600, height: 600).background(Theme.bg).foregroundStyle(.white)
        .environment(\.layoutDirection, .rightToLeft)
        let r = ImageRenderer(content: v); r.scale = 2
        return r.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: "bolt")
    }
}
