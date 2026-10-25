import SwiftUI
import Combine

/// Back of an iPhone drawn in SwiftUI, with the magnetometer area highlighted.
struct PhoneDiagram: View {
    var showLabel = true
    var compact = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sensorX") private var sx = 0.5
    @AppStorage("sensorY") private var sy = 0.45

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.16)
                    .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: w * 0.16)
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
                // camera bump (top-left when looking at the back)
                RoundedRectangle(cornerRadius: w * 0.09)
                    .fill(Color(white: 0.1))
                    .frame(width: w * 0.42, height: w * 0.42)
                    .overlay {
                        VStack(spacing: w * 0.04) {
                            Circle().fill(Color.black).overlay(Circle().stroke(.gray, lineWidth: 1)).frame(width: w * 0.15)
                            Circle().fill(Color.black).overlay(Circle().stroke(.gray, lineWidth: 1)).frame(width: w * 0.15)
                        }
                    }
                    .offset(x: w * 0.07, y: w * 0.07)
                // sensor zone: on recent iPhones the compass sits on the wireless-charging (MagSafe) flex
                // behind the back glass, roughly mid-back. Exact spot varies; user can pin it with SensorFinderView.
                ZStack {
                    Circle().fill(Theme.amber.opacity(0.25))
                        .frame(width: w * 0.42)
                        .scaleEffect(pulse ? 1.25 : 0.8)
                        .opacity(pulse ? 0.2 : 0.9)
                    Circle().fill(Theme.amber).frame(width: w * 0.14)
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: w * 0.09, weight: .bold)).foregroundStyle(.black)
                }
                .position(x: w * sx, y: h * sy)
                Image(systemName: "apple.logo").font(.system(size: w * 0.16)).foregroundStyle(.white.opacity(0.25))
                    .position(x: w / 2, y: h * 0.52)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .aspectRatio(0.49, contentMode: .fit)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement()
        .accessibilityLabel("ظهر الجوال، الدائرة الصفرا مكان الحساس التقريبي")
    }
}

/// Phone diagram with callout arrow and label.
struct SensorLocator: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PhoneDiagram().frame(height: 220)
            VStack(alignment: .leading, spacing: 10) {
                Label("الحساس هنا", systemImage: "arrow.left")
                    .font(.title3.bold()).foregroundStyle(Theme.amber)
                    .environment(\.layoutDirection, .leftToRight)
                Text(SensorInfo.hint)
                    .font(.body).fixedSize(horizontal: false, vertical: true)
                Label("الدائرة الصفرا = مكان الحساس", systemImage: "circle.fill")
                    .font(.callout).foregroundStyle(.secondary)
                NavigationLink { SensorFinderView() } label: {
                    Label("حدد مكانه بالضبط في جوالك", systemImage: "scope").font(.callout.bold())
                }
            }
            .padding(.top, 20)
        }
    }
}

/// Wall with bricks, a hidden wire and a phone sweeping slowly across it.
struct WallSweepView: View {
    var vertical = false
    @State private var t: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.55, green: 0.45, blue: 0.36))
                Canvas { ctx, size in
                    let bh: CGFloat = 22, bw: CGFloat = 50
                    var row = 0
                    var y: CGFloat = 0
                    while y < size.height {
                        let off: CGFloat = row % 2 == 0 ? 0 : bw / 2
                        var x: CGFloat = -off
                        while x < size.width {
                            ctx.stroke(Path(CGRect(x: x, y: y, width: bw, height: bh)), with: .color(.black.opacity(0.18)), lineWidth: 1)
                            x += bw
                        }
                        y += bh; row += 1
                    }
                    // hidden wire
                    var wire = Path()
                    wire.move(to: CGPoint(x: size.width * 0.62, y: 0))
                    wire.addLine(to: CGPoint(x: size.width * 0.62, y: size.height))
                    ctx.stroke(wire, with: .color(.red.opacity(0.55)), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Label("سلك مخفي", systemImage: "bolt.fill").font(.caption.bold())
                    .padding(6).background(.red.opacity(0.85), in: .capsule)
                    .position(x: w * 0.62, y: h - 18)
                // direction arrow
                Image(systemName: vertical ? "arrow.up.and.down" : "arrow.left.and.right")
                    .font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                    .shadow(radius: 3)
                    .position(x: vertical ? w * 0.18 : w / 2, y: vertical ? h / 2 : 22)
                PhoneDiagram(showLabel: false, compact: true)
                    .frame(height: h * 0.55)
                    .position(x: vertical ? w * 0.62 : w * (0.18 + 0.64 * t),
                              y: vertical ? h * (0.3 + 0.4 * t) : h * 0.55)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(height: 190)
        .onAppear {
            if reduceMotion { t = 0.5; return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { t = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(vertical ? "حرك الجوال ببطء فوق وتحت على الجدار" : "حرك الجوال ببطء يمين ويسار على الجدار")
    }
}

/// Colored legend of the gauge.
struct ColorLegend: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(ScanStatus.allCases, id: \.self) { s in
                HStack(spacing: 12) {
                    Image(systemName: s.icon).font(.title2).foregroundStyle(s.color).frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.headline).foregroundStyle(s.color)
                        Text(s.meaning).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

enum ScanStatus: CaseIterable {
    case safe, caution, danger
    init(score: Double) { self = score < 0.33 ? .safe : (score < 0.66 ? .caution : .danger) }
    var title: String {
        switch self { case .safe: "ما فيه إشارة واضحة"; case .caution: "إشارة متوسطة"; case .danger: "إشارة قوية" }
    }
    var meaning: String {
        switch self {
        case .safe: "ما فيه إشارة واضحة، وهذا ما يعني إن المكان خالي من الأسلاك. افصل الكهربا دايماً"
        case .caution: "المؤشر أصفر، فيه حديد أو سلك قريب. تحرك ببطء وتأكد"
        case .danger: "سلك أو معدن محتمل هنا، لا تخرم في هذا المكان"
        }
    }
    var icon: String {
        switch self { case .safe: "circle.dashed"; case .caution: "exclamationmark.triangle.fill"; case .danger: "bolt.trianglebadge.exclamationmark.fill" }
    }
    var color: Color {
        switch self { case .safe: Theme.ok; case .caution: Theme.amber; case .danger: Theme.danger }
    }
}

struct StepCard<Content: View>: View {
    var number: Int
    var title: String
    var text: String
    var icon: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("\(number)").font(.title2.bold()).foregroundStyle(.black)
                    .frame(width: 46, height: 46).background(Theme.amber, in: .circle)
                Text(title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: icon).font(.title).foregroundStyle(Theme.amber)
            }
            Text(text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

struct GuideSteps: View {
    var body: some View {
        VStack(spacing: 16) {
            StepCard(number: 1, title: "سوّ المعايرة بعيد عن الجدار", text: "وقف في نص الغرفة بعيد متر عن الجدران والأجهزة والحديد، واضغط ابدأ المعايرة وخل الجوال ثابت", icon: "scope") {
                HStack(spacing: 18) {
                    Image(systemName: "iphone").font(.system(size: 54))
                    Image(systemName: "arrow.left.and.right").font(.title.bold()).foregroundStyle(Theme.amber)
                    Text("١ متر").font(.title3.bold())
                    Image(systemName: "rectangle.split.3x3").font(.system(size: 54)).foregroundStyle(.brown)
                }
                .frame(maxWidth: .infinity)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            }
            StepCard(number: 2, title: "حط ظهر الجوال مسطّح على الجدار", text: "اقلب الجوال وخل ظهره كله ملاصق للجدار بدون ما تميله. الاتجاه ما يفرق لأن تيّار يقيس قوة المجال الكلية، المهم مكان الحساس (الدائرة الصفرا) يمر فوق المكان اللي تبي تفحصه", icon: "hand.point.up.left.fill") {
                SensorLocator()
            }
            StepCard(number: 3, title: "حرّكه ببطء يمين ويسار ثم فوق وتحت", text: "خله ملاصق للجدار ومرّره ببطء، تقريباً شبر كل ثانيتين، بدون ما تلفّه. اللي يتحرك بسرعة ما يلقط شي", icon: "arrow.up.and.down.and.arrow.left.and.right") {
                WallSweepView()
                WallSweepView(vertical: true)
            }
            StepCard(number: 4, title: "اقرأ لون المؤشر", text: "لو تغير اللون وزاد الصوت والرجة، وقف ولا تخرم في هالمكان", icon: "gauge.with.dots.needle.67percent") {
                ColorLegend()
            }
            SafetyCard()
        }
    }
}

struct SafetyCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill").font(.largeTitle).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 6) {
                Text("تنبيه سلامة مهم").font(.title3.bold())
                Text("تيّار ينبهك بس وما يضمن أبداً إن المكان آمن. عدم وجود تنبيه ما يعني إن ما فيه سلك. افصل الكهربا من الطبلون دايماً قبل الخرم، واستخدم جهاز كشف أسلاك حقيقي.")
                    .font(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.15), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.red.opacity(0.5), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

struct HowToView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { GuideSteps().padding() }
                .background(Theme.bg)
                .navigationTitle("كيف أستخدمه")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("تم") { dismiss() }.font(.headline)
                    }
                }
        }
    }
}


enum SensorInfo {
    /// Hardware model identifier via utsname, e.g. "iPhone17,1".
    static var model: String {
        var u = utsname(); uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
    static var hint: String {
        "في الآيفونات الحديثة حساس البوصلة على شريحة الشحن اللاسلكي خلف الزجاج، تقريباً في نص ظهر الجوال وليس جنب الكاميرا. المكان الدقيق يختلف حسب الموديل، فحدده مرة وحدة بأداة التحديد"
    }
}

/// Sensor-location test v2: 3×5 grid, per-cell robust peak delta vs a reference with repeated samples,
/// refinement of the top cells, confidence score with automatic retries, sub-cell centroid and a
/// plausibility check against the MagSafe-area expectation. Pure maths lives in `LocatorCore`.
struct SensorFinderView: View {
    @Environment(SensorEngine.self) private var engine
    @AppStorage("sensorX") private var sx = 0.5
    @AppStorage("sensorY") private var sy = 0.45
    @AppStorage("sensorConfidence") private var savedConf = 0.0
    enum Step { case intro, reference, place, settle, lift, result }
    @State private var step: Step = .intro
    @State private var core = LocatorCore()
    @State private var queue: [Int] = []
    @State private var done = 0
    @State private var planned = 18
    @State private var round = 0          // 0 coarse, 1 refine, 2+ retries
    @State private var ref = 0.0
    @State private var buf: [Double] = []
    @State private var stepStart = Date()
    @State private var overSince: Date?
    @State private var result: LocatorCore.Result?
    @State private var saved = false
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private var cell: Int { queue.first ?? 0 }
    private var live: Double { abs(engine.currentMagnitude - ref) }
    private var thr: Double { max(1.5, 4 * core.noise) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if step != .intro {
                    ProgressView(value: Double(min(done, planned)), total: Double(planned)).tint(Theme.amber)
                        .accessibilityLabel("التقدم \(done) من \(planned)")
                }
                switch step {
                case .intro: intro
                case .reference:
                    title("خل الجوال على الطاولة بدون المفتاح")
                    ProgressView().controlSize(.large).padding()
                    caption("نقيس الهدوء ثانيتين…")
                case .place, .settle, .lift:
                    title(step == .lift ? "شيل المفتاح" : (step == .settle ? "ثبّته…" : "حط المفتاح هنا"))
                    caption(round == 0 ? "المسح \(done + 1) من ١٥" : (round == 1 ? "تأكيد أقوى الأماكن" : "إعادة الأماكن المتقاربة"))
                    grid(active: cell, values: nil)
                    HStack(spacing: 8) {
                        Text("التغير").foregroundStyle(Theme.secondary)
                        Text(String(format: "%.1f µT", live)).font(Theme.mono(18)).foregroundStyle(live > thr ? Theme.amber : Theme.text)
                            .environment(\.layoutDirection, .leftToRight)
                    }.accessibilityElement(children: .combine)
                case .result:
                    if let r = result { resultView(r) }
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationTitle("مكان الحساس")
        .onAppear {
            engine.start()
            #if DEBUG
            if UserDefaults.standard.string(forKey: "demoScreen") == "finder" {   // simulator screenshot fixture
                var c = LocatorCore()
                for i in 0..<c.count { let p = c.center(i), dx = (p.x - 0.52) * 7, dy = (p.y - 0.5) * 15; c.add(cell: i, delta: 120 / pow(dx * dx + dy * dy + 1, 1.5)) }
                core = c; result = c.result(); done = 18; step = .result
            }
            #endif
        }
        .onReceive(timer) { _ in tick() }
        .sensoryFeedback(.selection, trigger: done)
        .sensoryFeedback(.success, trigger: step == .result)
    }

    private var intro: some View {
        VStack(spacing: 20) {
            grid(active: nil, values: nil).frame(height: 300).accessibilityHidden(true)
            title("نحدد مكان الحساس بدقة")
            VStack(alignment: .leading, spacing: 14) {
                bullet(1, "اقلب الجوال على وجهه فوق طاولة خشب، وشيل الكفر")
                bullet(2, "امسك مفتاح حديد أو مغناطيس ثلاجة صغير")
                bullet(3, "حطه على كل مربع ينوّر، والتطبيق يقيس ويكمّل لحاله (١٥ مربع + تأكيد)")
            }
            Button { restart() } label: { Text("ابدأ") }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private func resultView(_ r: LocatorCore.Result) -> some View {
        VStack(spacing: 18) {
            title(r.confidence >= 0.55 ? "لقينا مكان الحساس" : "النتيجة غير أكيدة")
            grid(active: nil, values: (0..<core.count).map { core.value($0) }, marker: (r.x, r.y))
            HStack(spacing: 12) {
                stat("الثقة", "\(Int(r.confidence * 100))%", r.confidence >= 0.55 ? Theme.ok : Theme.amber)
                stat("أقوى تغير", String(format: "%.1f µT", r.signal), Theme.text)
            }
            Panel {
                Label(r.plausible ? "يطابق المتوقع: في الآيفونات الحديثة الحساس على شريحة الشحن اللاسلكي (MagSafe) قرب نص الظهر"
                                  : "مكان غير متوقع. في أغلب الآيفونات الحديثة الحساس قرب نص الظهر. أعد الاختبار بمغناطيس صغير وبدون كفر",
                      systemImage: r.plausible ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(r.plausible ? Theme.text : Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            Button { sx = r.x; sy = r.y; savedConf = r.confidence; saved = true } label: { Text(saved ? "تم الحفظ ✓" : "احفظ المكان") }
                .buttonStyle(PrimaryButtonStyle()).disabled(saved)
            Button { restart() } label: { Text("أعد الاختبار") }.buttonStyle(SecondaryButtonStyle())
        }
    }

    /// Back of the phone with a dashed 3×5 grid; optional heat-map values and result marker.
    private func grid(active: Int?, values: [Double]?, marker: (Double, Double)? = nil) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, mx = values?.max() ?? 0
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.14).fill(Theme.surface)
                RoundedRectangle(cornerRadius: w * 0.14).stroke(Theme.stroke, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: w * 0.07).fill(Color.black).frame(width: w * 0.36, height: w * 0.36)
                    .position(x: w * 0.24, y: w * 0.24)
                Circle().stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(width: w * 0.62)
                    .position(x: w * 0.5, y: h * 0.52)   // MagSafe ring (expected area)
                ForEach(0..<core.count, id: \.self) { i in
                    let p = core.center(i), cw = w / CGFloat(core.cols) * 0.8, ch = h * 0.82 / CGFloat(core.rows) * 0.8
                    let v = values.map { mx > 0 ? $0[i] / mx : 0 } ?? 0
                    RoundedRectangle(cornerRadius: 8)
                        .fill(i == active ? Theme.amber : Theme.amber.opacity(values == nil ? 0 : 0.08 + 0.8 * v))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == active ? Theme.amber : Theme.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: i == active ? [] : [4, 4])))
                        .overlay { if i == active { Image(systemName: "key.fill").foregroundStyle(.black).font(.system(size: cw * 0.35, weight: .bold)) } }
                        .frame(width: cw, height: ch)
                        .position(x: w * p.x, y: h * p.y)
                }
                if let m = marker {
                    Circle().stroke(Theme.ok, lineWidth: 3).frame(width: w * 0.16)
                        .overlay(Circle().fill(Theme.ok).frame(width: 8))
                        .position(x: w * m.0, y: h * m.1)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .aspectRatio(0.49, contentMode: .fit)
        .frame(maxHeight: 380)
        .animation(.easeInOut(duration: 0.2), value: active)
        .accessibilityElement()
        .accessibilityLabel(active.map { "ظهر الجوال، المربع \($0 + 1) من ١٥ منوّر" } ?? "ظهر الجوال مع خريطة القراءات")
    }

    private func stat(_ k: String, _ v: String, _ c: Color) -> some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(k).font(.caption).foregroundStyle(Theme.secondary)
                Text(v).font(Theme.mono(22)).foregroundStyle(c).environment(\.layoutDirection, .leftToRight)
            }
        }.accessibilityElement(children: .combine)
    }
    private func title(_ t: String) -> some View { Text(t).font(.title.bold()).foregroundStyle(Theme.text).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
    private func caption(_ t: String) -> some View { Text(t).font(.callout).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
    private func bullet(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(Theme.mono(17, .bold)).foregroundStyle(.black).frame(width: 32, height: 32).background(Theme.amber, in: .circle)
            Text(t).font(.body).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restart() {
        core = LocatorCore(); queue = Array(0..<core.count); done = 0; planned = core.count + 3; round = 0
        buf = []; saved = false; result = nil; step = .reference; stepStart = Date()
    }

    private func tick() {
        let m = engine.currentMagnitude
        guard m > 0 else { return }
        let now = Date(), el = now.timeIntervalSince(stepStart)
        switch step {
        case .intro, .result: break
        case .reference:
            buf.append(m)
            if el > 2, buf.count > 10 {
                let s = buf.sorted(); ref = s[s.count / 2]
                let mean = buf.reduce(0, +) / Double(buf.count)
                core.noise = max(0.1, (buf.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(buf.count)).squareRoot())
                go(.place)
            }
        case .place:
            buf.append(m)
            if live > thr { overSince = overSince ?? now } else { overSince = nil }
            if let o = overSince, now.timeIntervalSince(o) > 0.3 { go(.settle) }
            else if el > 6 { record(LocatorCore.peakDelta(buf, reference: ref, noise: core.noise), needsLift: false) }  // nothing here
        case .settle:
            buf.append(m)
            if el > 1.0 { record(LocatorCore.peakDelta(buf, reference: ref, noise: core.noise), needsLift: true) }
        case .lift:
            buf.append(m)
            if live < thr { overSince = overSince ?? now } else { overSince = nil }
            if let o = overSince, now.timeIntervalSince(o) > 0.3 {
                let s = buf.suffix(6).sorted(); ref = 0.8 * ref + 0.2 * s[s.count / 2]   // follow slow drift
                advance()
            } else if el > 4 { advance() }
        }
    }
    private func go(_ s: Step) { step = s; stepStart = Date(); buf = []; overSince = nil }
    private func record(_ d: Double, needsLift: Bool) {
        core.add(cell: cell, delta: d); done += 1
        if needsLift { go(.lift) } else { advance() }
    }
    private func advance() {
        if !queue.isEmpty { queue.removeFirst() }
        if queue.isEmpty {
            if round == 0 { queue = Array(core.ranked.prefix(3)); round = 1 }
            else {
                let r = core.result()
                if !r.retry.isEmpty && round < 3 { queue = r.retry; planned += r.retry.count; round += 1 }
                else { result = r; go(.result); return }
            }
        }
        go(.place)
    }
}
