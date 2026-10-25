import SwiftUI
import Charts

struct OnboardingView: View {
    var done: () -> Void
    @State private var agreed = false
    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 64)).foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Text("تيّار").font(.largeTitle.bold()).frame(maxWidth: .infinity)
                Text("قبل لا تخرم الجدار، مرّر جوالك عليه وتيّار يعطيك تقدير تقريبي لوجود سلك عليه حمل أو حديد. تقدير مساعد وليس جهاز سلامة").font(.title3).multilineTextAlignment(.center).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                GuideSteps()
                Toggle("فاهم إن التطبيق للتنبيه بس وما يغني عن فصل الكهربا", isOn: $agreed)
                    .font(.body.bold()).toggleStyle(.switch).tint(Theme.amber).padding().background(Theme.card, in: .rect(cornerRadius: 14))
                Button(action: done) { Text("ابدأ") }
                    .buttonStyle(PrimaryButtonStyle(tint: agreed ? Theme.amber : Theme.surface2)).disabled(!agreed)
            }
            .padding()
        }
        .background(Theme.bg)
        }
    }
    private func card(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding().background(Theme.card, in: .rect(cornerRadius: 14))
    }
}

/// Instrument gauge: 270° arc with ticks, monospaced readout. Colour + text label (never colour alone).
struct GaugeView: View {
    var score: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().trim(from: 0.125, to: 0.875)
                .stroke(Theme.surface2, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(90))
            ForEach(0..<28, id: \.self) { i in
                let major = i % 9 == 0
                Capsule().fill(Theme.stroke.opacity(major ? 1 : 0.7))
                    .frame(width: major ? 3 : 1.5, height: major ? 12 : 7)
                    .offset(y: -128)
                    .rotationEffect(.degrees(-135 + Double(i) * 270 / 27))
            }
            Circle().trim(from: 0.125, to: 0.125 + 0.75 * max(0.002, score))
                .stroke(Theme.level(score), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(90))
                .shadow(color: Theme.level(score).opacity(0.35), radius: 10)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: score)
            VStack(spacing: 6) {
                Text(verbatim: "\(Int((score * 100).rounded()))").font(Theme.mono(78, .bold)).monospacedDigit()
                    .foregroundStyle(Theme.level(score)).contentTransition(.numericText())
                Text(label).font(.headline).foregroundStyle(Theme.text).multilineTextAlignment(.center).padding(.horizontal, 48)
            }
        }
        .frame(width: 290, height: 290)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("قوة الإشارة \(Int(score * 100)) بالمية، \(label)")
        .accessibilityAddTraits(.updatesFrequently)
    }
    var label: String { ScanStatus(score: score).title }
}

struct ScanView: View {
    @Environment(SensorEngine.self) private var engine
    @State private var feedback = FeedbackController()
    @AppStorage("sound") private var sound = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("geiger") private var geiger = false
    @State private var scanning = false
    @State private var showHelp = false
    @State private var sessionPeak = 0.0
    @State private var shareCard: Image?
    @State private var zeroNote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !engine.available {
                        ContentUnavailableView("ما فيه حساس مغناطيس", systemImage: "xmark.octagon", description: Text("جهازك ما يدعم حساس المغناطيس"))
                    } else if engine.baselineMagnitude == nil {
                        CalibrateView()
                    } else {
                        header
                        banners
                        GaugeView(score: scanning ? engine.score : 0).padding(.vertical, 4)
                        Text(scanning ? ScanStatus(score: engine.score).meaning : "اضغط ابدأ الفحص وحط ظهر الجوال مسطّح على الجدار")
                            .font(.callout).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        HStack(spacing: 12) {
                            tile("معدن", value: String(format: "%.0f µT", engine.magDeviation), level: engine.magScore, likely: engine.metalLikely)
                            tile(engine.mainsHz == 60 ? "ذبذبة ٦٠Hz" : "ذبذبة ٥٠Hz", value: engine.humMeasurable ? String(format: "×%.1f", engine.humRatio) : "—", level: engine.humScore, likely: engine.humLikely)
                        }
                        HStack(spacing: 12) {
                            Panel(padding: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("أعلى قراءة").font(.caption).foregroundStyle(Theme.secondary)
                                        Text(verbatim: "\(Int(sessionPeak * 100))").font(Theme.mono(22)).foregroundStyle(Theme.level(sessionPeak))
                                    }
                                    Spacer()
                                    Button { sessionPeak = 0 } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                                        .accessibilityLabel("صفّر أعلى قراءة").foregroundStyle(Theme.secondary)
                                }
                            }
                            Button { engine.zero(); zeroNote = true } label: {
                                VStack(spacing: 4) { Image(systemName: "scope").font(.title3); Text("تصفير").font(.subheadline.bold()) }
                                    .frame(width: 96).frame(minHeight: 72)
                            }
                            .buttonStyle(SecondaryButtonStyle()).frame(width: 96)
                            .accessibilityHint("يخلي القراءة الحالية هي الصفر")
                        }
                        Button {
                            scanning.toggle()
                            UIApplication.shared.isIdleTimerDisabled = scanning
                            if scanning { feedback.start(); shareCard = nil; sessionPeak = 0 }
                            else { feedback.stop(); if sessionPeak > 0.05 { shareCard = ResultCard.render(peak: sessionPeak) } }
                        } label: { Label(scanning ? "وقف الفحص" : "ابدأ الفحص", systemImage: scanning ? "stop.fill" : "play.fill") }
                        .buttonStyle(PrimaryButtonStyle(tint: scanning ? Theme.danger : Theme.amber))
                        .sensoryFeedback(.impact(weight: .medium), trigger: scanning)
                        if !scanning, let card = shareCard {
                            ShareLink(item: card, preview: SharePreview("نتيجة تيّار", image: card)) {
                                Label("شارك النتيجة", systemImage: "square.and.arrow.up")
                            }.buttonStyle(SecondaryButtonStyle())
                        }
                        liveGraph
                        Button { stopAndRecal() } label: { Label("أعد المعايرة", systemImage: "arrow.triangle.2.circlepath") }
                            .buttonStyle(SecondaryButtonStyle())
                        Text("تقدير مساعد وليس جهاز سلامة، وممكن يفوّت أسلاك. افصل الكهربا من الطبلون واستخدم جهاز كشف احترافي قبل الخرم. يلقط السلك اللي عليه حمل، والحديد والمسامير تبان في مؤشر المعدن.")
                            .font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showHelp) { HowToView() }
            .onAppear {
                engine.start()
                #if DEBUG
                if let v = UserDefaults.standard.string(forKey: "demoScore"), let d = Double(v) { scanning = true; sessionPeak = d }
                #endif
            }
            .onDisappear { scanning = false; feedback.stop(); UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: engine.rawMagnitude) {
                guard scanning else { return }
                feedback.soundOn = sound; feedback.hapticsOn = haptics; feedback.geiger = geiger
                feedback.update(score: engine.score)
                sessionPeak = max(sessionPeak, engine.score)
            }
            .onChange(of: engine.metalLikely) { _, on in
                guard scanning, on else { return }
                ScanHistory.add(ScanRecord(date: .now, kind: "metal", peak: Int(engine.score * 100)))
            }
            .onChange(of: engine.humLikely) { _, on in
                guard scanning, on else { return }
                ScanHistory.add(ScanRecord(date: .now, kind: "wire", peak: Int(engine.score * 100)))
            }
            .onChange(of: engine.autoZeroCount) { o, n in if n > o { zeroNote = true } }
            .task(id: zeroNote) { if zeroNote { try? await Task.sleep(for: .seconds(3)); zeroNote = false } }
        }
    }

    private func stopAndRecal() { scanning = false; feedback.stop(); sessionPeak = 0; UIApplication.shared.isIdleTimerDisabled = false; engine.resetBaseline() }

    private var header: some View {
        HStack {
            Button { showHelp = true } label: { Image(systemName: "questionmark.circle").font(.title2).frame(width: 44, height: 44) }
                .accessibilityLabel("كيف أستخدمه").foregroundStyle(Theme.secondary)
            Spacer()
            Text("تيّار").font(.title2.bold()).foregroundStyle(Theme.text)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: engine.needsRecalibration ? "exclamationmark.circle" : "checkmark.circle")
                Text(engine.needsRecalibration ? "معايرة" : "معاير")
            }
            .font(.subheadline).foregroundStyle(engine.needsRecalibration ? Theme.amber : Theme.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityElement(children: .combine)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var banners: some View {
        if engine.needsRecalibration {
            notice("القراءة انحرفت. أعد المعايرة بعيد عن الجدار", icon: "arrow.triangle.2.circlepath", color: Theme.amber) { stopAndRecal() }
        }
        if (engine.baselineMagnitude ?? 0) > 110 {
            notice("فيه مغناطيس قريب (كفر أو محفظة MagSafe؟). شيله وأعد المعايرة", icon: "exclamationmark.triangle", color: Theme.amber, action: nil)
        }
        if engine.suppressedByMotion {
            notice("حركتك سريعة، حرّك الجوال ببطء", icon: "tortoise", color: Theme.amber, action: nil)
        }
        if zeroNote {
            notice("تم التصفير على القراءة الحالية", icon: "scope", color: Theme.secondary, action: nil)
                .transition(.opacity)
        }
    }

    private func notice(_ t: String, icon: String, color: Color, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(t).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.callout.weight(.semibold)).foregroundStyle(color)
            .padding(12).background(color.opacity(0.10), in: .rect(cornerRadius: Theme.R.s))
            .overlay(RoundedRectangle(cornerRadius: Theme.R.s).stroke(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(action == nil)
    }

    private func tile(_ title: String, value: String, level: Double, likely: Bool) -> some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(Theme.secondary)
                    Spacer()
                    if likely && scanning { Text("محتمل").font(.caption.bold()).foregroundStyle(Theme.level(level)) }
                }
                Text(value).font(Theme.mono(24)).foregroundStyle(Theme.text).monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule().fill(Theme.level(level)).frame(width: g.size.width * (scanning ? level : 0))
                    }
                }
                .frame(height: 5).environment(\.layoutDirection, .leftToRight)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var liveGraph: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("المجال المغناطيسي مباشر").font(.subheadline.bold()).foregroundStyle(Theme.text)
                Chart(engine.history) { p in
                    LineMark(x: .value("t", p.id), y: .value("µT", p.value)).foregroundStyle(Theme.amber).interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.stroke); AxisValueLabel().font(.caption2.monospaced()) } }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 110)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("رسم المجال المغناطيسي المباشر")
    }
}

struct CalibrateView: View {
    @Environment(SensorEngine.self) private var engine
    var body: some View {
        VStack(spacing: 20) {
            Text("المعايرة").font(.largeTitle.bold()).foregroundStyle(Theme.text).padding(.top, 32)
            ZStack {
                Circle().stroke(Theme.surface2, lineWidth: 10)
                Circle().trim(from: 0, to: engine.calibrating ? engine.calibrationProgress : 0)
                    .stroke(engine.calibrationTooNoisy ? Theme.danger : Theme.amber, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: engine.calibrationProgress)
                VStack(spacing: 4) {
                    Text(verbatim: "\(Int(engine.calibrationProgress * 100))%").font(Theme.mono(40, .bold)).foregroundStyle(Theme.text)
                    Text("١ متر عن الجدار").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 200, height: 200)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("تقدم المعايرة \(Int(engine.calibrationProgress * 100)) بالمية")
            Text("امسك الجوال بعيد عن الجدران والأجهزة والحديد بمسافة متر تقريباً، وخله ثابت لين تخلص المعايرة")
                .font(.body).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if engine.calibrating {
                Text(engine.calibrationTooNoisy ? "فيه حركة أو معدن قريب، ثبّت الجوال بعيد عن الجدار" : "جاري المعايرة، خله ثابت")
                    .font(.headline).foregroundStyle(engine.calibrationTooNoisy ? Theme.danger : Theme.amber).multilineTextAlignment(.center)
            } else {
                Button { engine.beginCalibration() } label: { Label("ابدأ المعايرة", systemImage: "scope") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Text("دقة البوصلة: \(engine.calibrationAccuracy) · \(Int(engine.rawRate)) قراءة/ث").font(.caption).foregroundStyle(Theme.secondary)
        }
        .sensoryFeedback(.success, trigger: engine.calibrating) { was, now in was && !now }
    }
}

struct TestModeView: View {
    @Environment(SensorEngine.self) private var engine
    @State private var traceURL: URL?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    debugGrid
                } header: { Text("قراءة مباشرة للتشخيص") } footer: {
                    Text("الفرق = |المجال بعد الفلترة − الأساس|. لما تبعد الجوال عن الحديد لازم الفرق ونقاط المعدن ينزلون للصفر خلال أقل من ثانية. لو ثبت فرق كبير ٦ ثواني، تيّار يصفّر تلقائياً")
                }
                Section("سرعة الحساس الفعلية") {
                    row("المغناطيس الخام", String(format: "%.1f Hz", engine.rawRate))
                    row("حركة الجهاز", String(format: "%.1f Hz", engine.motionRate))
                    row("تردد الكهربا يطلع عند", String(format: "%.1f Hz", engine.aliasFrequency))
                    if engine.rawRate > 0 && engine.rawRate < 30 {
                        Text("سرعة الحساس قليلة، كشف ذبذبة الكهربا غالباً ما بيشتغل على جوالك").foregroundStyle(Theme.danger).font(.footnote)
                    }
                }
                Section("المحاور الخام") {
                    row("X", String(format: "%.1f µT", engine.rawField.x))
                    row("Y", String(format: "%.1f µT", engine.rawField.y))
                    row("Z", String(format: "%.1f µT", engine.rawField.z))
                    row("إزاحة الجوال الداخلية (مثبتة)", String(format: "%.0f µT", engine.hardIronMagnitude))
                    row("مصدرها", engine.usingCalibratedField ? "تقدير iOS وقت المعايرة" : "غير متوفر (خام)")
                    row("دقة بوصلة iOS", engine.calibrationAccuracy)
                }
                Section {
                    Chart {
                        RectangleMark(xStart: .value("من", max(0, engine.aliasFrequency - 2)), xEnd: .value("إلى", engine.aliasFrequency + 2))
                            .foregroundStyle(Theme.amber.opacity(0.15))
                        ForEach(engine.spectrum) { p in
                            LineMark(x: .value("Hz", p.freq), y: .value("قوة", log10(max(p.power, 1e-6)))).foregroundStyle(Theme.amber)
                        }
                    }
                    .chartXAxisLabel("Hz").frame(height: 200).environment(\.layoutDirection, .leftToRight)
                } header: { Text("الطيف الترددي") } footer: {
                    Text("قرّب الجوال من سلك شغال (شاحن لابتوب أو مكيف شغال) وشوف هل يطلع ارتفاع في المنطقة الصفرا")
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(engine.recording ? "وقف التسجيل (\(engine.recordedLines))" : "سجّل قراءات للتطوير") { traceURL = nil; engine.toggleRecording() }
                        .buttonStyle(.bordered)
                    if !engine.recording, engine.recordedLines > 1 {
                        if let url = traceURL { ShareLink("صدّر CSV", item: url).buttonStyle(.borderedProminent) }
                        else { Button("جهّز الملف") { traceURL = engine.exportTrace() }.buttonStyle(.borderedProminent) }
                    }
                }.padding(8).font(.footnote).tint(Theme.amber)
            }
            .navigationTitle("وضع التجربة")
            .onAppear { engine.start() }
        }
    }
    private var debugGrid: some View {
        let cells: [(String, String, Color)] = [
            ("الخام µT", String(format: "%.1f", engine.rawMagnitude), Theme.text),
            ("المجال µT", String(format: "%.1f", engine.fieldMagnitude), Theme.text),
            ("بعد الفلترة", String(format: "%.1f", engine.filteredMagnitude), Theme.text),
            ("الأساس µT", engine.baselineMagnitude.map { String(format: "%.1f", $0) } ?? "—", Theme.text),
            ("الفرق µT", String(format: "%.1f", engine.magDeviation), Theme.level(engine.magScore)),
            ("نقاط المعدن", "\(Int(engine.magScore * 100))", Theme.level(engine.magScore)),
            ("نقاط الذبذبة", "\(Int(engine.humScore * 100))", Theme.level(engine.humScore)),
            ("SNR dB", String(format: "%.1f", engine.hfVariance), Theme.text),
            ("تصفير تلقائي", "\(engine.autoZeroCount)", Theme.text),
            ("الحالة", engine.phaseName, Theme.secondary),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(cells, id: \.0) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.0).font(.caption).foregroundStyle(Theme.secondary)
                    Text(c.1).font(Theme.mono(20)).foregroundStyle(c.2).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }
    private func row(_ k: String, _ v: String) -> some View {
        LabeledContent(k) { Text(v).monospacedDigit() }
    }
}

struct SettingsView: View {
    @Environment(SensorEngine.self) private var engine
    @AppStorage("sound") private var sound = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("geiger") private var geiger = false
    @AppStorage("onboarded") private var onboarded = true
    @State private var showHelp = false
    var body: some View {
        @Bindable var e = engine
        NavigationStack {
            Form {
                Section("التنبيه") {
                    Toggle("الصوت", isOn: $sound)
                    Toggle("صوت عدّاد (طقطقة تزيد كل ما قربت)", isOn: $geiger)
                    Toggle("الرجة", isOn: $haptics)
                }
                Section {
                    Picker("الحساسية", selection: $e.sensitivity) {
                        Text("منخفضة").tag(0.6); Text("عادية").tag(1.0); Text("عالية").tag(1.6)
                    }.pickerStyle(.segmented)
                } header: { Text("الحساسية") } footer: { Text("العالية تلقط الحديد الأبعد لكن تتأثر أكثر بالحركة. العادية مناسبة لأغلب الجدران") }
                Section("أدوات") {
                    NavigationLink("سجل الفحص") { HistoryView() }
                    NavigationLink("ميزان الاستواء") { LevelView() }
                    NavigationLink("الفرق بين الحديد والسلك") { ExplainView() }
                }
                Section("نطاق ذبذبة الكهربا") {
                    Picker("تردد الكهربا", selection: $e.mainsHz) {
                        Text("٦٠ هيرتز").tag(60.0)
                        Text("٥٠ هيرتز").tag(50.0)
                    }
                    .pickerStyle(.segmented)
                    Text("السعودية ٦٠ هيرتز").font(.callout).foregroundStyle(.secondary)
                    Toggle("حساب النطاق تلقائي", isOn: $e.autoBand)
                    if !e.autoBand {
                        Stepper(String(format: "من %.0f Hz", e.bandLow), value: $e.bandLow, in: 1...(e.bandHigh - 1))
                        Stepper(String(format: "إلى %.0f Hz", e.bandHigh), value: $e.bandHigh, in: (e.bandLow + 1)...50)
                    }
                }
                Section {
                    Button("أعد المعايرة") { engine.resetBaseline() }
                    NavigationLink("حدد مكان الحساس في جوالك") { SensorFinderView() }
                    Button("كيف أستخدمه") { showHelp = true }
                    Button("اعرض تنبيه السلامة مرة ثانية") { onboarded = false }
                } footer: {
                    Text("تيّار ينبهك بس وما يضمن إن المكان آمن. افصل الكهربا واستخدم جهاز كشف أسلاك حقيقي.")
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("الإعدادات")
            .sheet(isPresented: $showHelp) { HowToView() }
        }
    }
}
