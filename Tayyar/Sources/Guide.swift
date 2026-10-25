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
        switch self { case .safe: .green; case .caution: Theme.amber; case .danger: .red }
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

/// Guided wizard: the app highlights one spot at a time, detects the key automatically, then shows the result.
struct SensorFinderView: View {
    @Environment(SensorEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sensorX") private var sx = 0.5
    @AppStorage("sensorY") private var sy = 0.45
    enum Step { case intro, reference, cell, lift, result }
    @State private var step: Step = .intro
    @State private var cell = 0
    @State private var ref = 0.0
    @State private var refSamples: [Double] = []
    @State private var peaks: [Double] = Array(repeating: 0, count: 6)
    @State private var cellStart = Date()
    @State private var aboveSince: Date?
    @State private var saved = false
    private let cols = 2, rows = 3
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private func center(_ i: Int) -> CGPoint { CGPoint(x: (Double(i % cols) + 0.5) / Double(cols), y: 0.12 + (Double(i / cols) + 0.5) / Double(rows) * 0.8) }
    private var live: Double { abs(engine.currentMagnitude - ref) }
    private var best: Int { peaks.indices.max { peaks[$0] < peaks[$1] } ?? 2 }
    private var progress: Double {
        switch step { case .intro, .reference: 0; case .cell, .lift: Double(cell) / 6; case .result: 1 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if step != .intro { ProgressView(value: progress).scaleEffect(y: 2.5).tint(Theme.amber) }
                switch step {
                case .intro: intro
                case .reference:
                    big("خل الجوال على الطاولة وشيل المفتاح بعيد")
                    ProgressView().scaleEffect(2).padding()
                    small("ثانيتين بس…")
                case .cell, .lift:
                    big(step == .cell ? "حط المفتاح هنا" : "ممتاز، شيل المفتاح")
                    phone(highlight: cell, arrow: step == .cell)
                    small(step == .cell ? "على ظهر الجوال، مكان الدائرة الصفرا بالضبط. انتظر شوي" : "ارفع المفتاح عن الجوال")
                    Text("المكان \(cell + 1) من ٦").font(.title3.bold())
                case .result:
                    big("لقينا مكان الحساس")
                    phone(highlight: best, arrow: false, found: true)
                    small(peaks[best] > 3 ? "هذا المكان هو اللي تمرره على الجدار وقت الفحص" : "ما بان فرق واضح، جرّب مفتاح أو مفك حديد أكبر")
                    Button {
                        let c = center(best); sx = c.x; sy = c.y; saved = true
                    } label: { Text(saved ? "تم الحفظ ✓" : "احفظ").font(.title.bold()).frame(maxWidth: .infinity, minHeight: 64) }
                        .buttonStyle(.borderedProminent).disabled(saved)
                    Button("أعد من البداية") { restart() }.font(.title3).buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .background(Theme.bg)
        .navigationTitle("مكان الحساس")
        .onAppear { engine.start() }
        .onReceive(timer) { _ in tick() }
    }

    private var intro: some View {
        VStack(spacing: 22) {
            HStack(spacing: 24) {
                Image(systemName: "iphone.gen3").font(.system(size: 90)).rotationEffect(.degrees(180)).foregroundStyle(.white)
                Image(systemName: "key.fill").font(.system(size: 64)).foregroundStyle(Theme.amber)
            }.padding(.top, 10).accessibilityHidden(true)
            big("نلقى مكان الحساس في جوالك")
            VStack(alignment: .leading, spacing: 16) {
                bullet(1, "اقلب الجوال على وجهه فوق طاولة")
                bullet(2, "امسك مفتاح حديد بيدك")
                bullet(3, "حط المفتاح وين ما نقول لك، والتطبيق يكمّل لحاله")
            }
            Button { restart() } label: { Text("ابدأ").font(.title.bold()).frame(maxWidth: .infinity, minHeight: 64) }
                .buttonStyle(.borderedProminent)
        }
    }

    private func phone(highlight: Int, arrow: Bool, found: Bool = false) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, c = center(highlight)
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.16).fill(Color(white: 0.22))
                RoundedRectangle(cornerRadius: w * 0.16).stroke(.white.opacity(0.4), lineWidth: 2)
                RoundedRectangle(cornerRadius: w * 0.08).fill(Color(white: 0.08)).frame(width: w * 0.38, height: w * 0.38)
                    .position(x: w * 0.26, y: w * 0.26)
                ForEach(0..<6, id: \.self) { i in
                    let p = center(i)
                    Circle().stroke(.white.opacity(0.25), lineWidth: 2).frame(width: w * 0.22).position(x: w * p.x, y: h * p.y)
                }
                Circle().fill(found ? Color.green : Theme.amber).frame(width: w * 0.3)
                    .overlay(Image(systemName: found ? "checkmark" : "key.fill").font(.system(size: w * 0.12, weight: .bold)).foregroundStyle(.black))
                    .position(x: w * c.x, y: h * c.y)
                if arrow {
                    Image(systemName: "arrow.down").font(.system(size: w * 0.18, weight: .heavy)).foregroundStyle(Theme.amber)
                        .position(x: w * c.x, y: h * c.y - w * 0.3)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .aspectRatio(0.49, contentMode: .fit)
        .frame(height: 360)
        .animation(.easeInOut, value: highlight)
        .accessibilityLabel("رسمة ظهر الجوال، المكان المحدد \(highlight + 1)")
    }

    private func big(_ t: String) -> some View { Text(t).font(.largeTitle.bold()).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
    private func small(_ t: String) -> some View { Text(t).font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true) }
    private func bullet(_ n: Int, _ t: String) -> some View {
        HStack(spacing: 14) {
            Text("\(n)").font(.title.bold()).foregroundStyle(.black).frame(width: 48, height: 48).background(Theme.amber, in: .circle)
            Text(t).font(.title2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func restart() {
        peaks = Array(repeating: 0, count: 6); cell = 0; refSamples = []; saved = false
        step = .reference; cellStart = Date()
    }

    private func tick() {
        let m = engine.currentMagnitude
        guard m > 0 else { return }
        let now = Date()
        switch step {
        case .intro, .result: break
        case .reference:
            refSamples.append(m)
            if now.timeIntervalSince(cellStart) > 2 {
                ref = refSamples.sorted()[refSamples.count / 2]
                step = .cell; cellStart = now; aboveSince = nil
            }
        case .cell:
            peaks[cell] = max(peaks[cell], live)
            if live > 4 { aboveSince = aboveSince ?? now } else { aboveSince = nil }
            let gotIt = aboveSince.map { now.timeIntervalSince($0) > 1.2 } ?? false
            let timeout = now.timeIntervalSince(cellStart) > 5   // far from sensor: little change, move on
            if gotIt || timeout { step = gotIt ? .lift : .cell; if !gotIt { next(now) } else { cellStart = now } }
        case .lift:
            if live < 2 || now.timeIntervalSince(cellStart) > 4 { next(now) }
        }
    }
    private func next(_ now: Date) {
        if cell >= 5 { step = .result; return }
        cell += 1; step = .cell; cellStart = now; aboveSince = nil
    }
}
