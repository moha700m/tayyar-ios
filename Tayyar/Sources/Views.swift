import SwiftUI
import Charts

struct OnboardingView: View {
    var done: () -> Void
    @State private var agreed = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 64)).foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Text("تيّار").font(.largeTitle.bold()).frame(maxWidth: .infinity)
                Text("قبل لا تخرم الجدار، مرّر جوالك عليه وتيّار ينبهك لو حس بسلك كهربا شغال أو حديد").font(.title3).multilineTextAlignment(.center).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                GuideSteps()
                Toggle("فاهم إن التطبيق للتنبيه بس وما يغني عن فصل الكهربا", isOn: $agreed)
                    .font(.body.bold()).toggleStyle(.switch).padding().background(Theme.card, in: .rect(cornerRadius: 14))
                Button(action: done) {
                    Text("ابدأ").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16)).disabled(!agreed)
            }
            .padding()
        }
        .background(Theme.bg)
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

struct GaugeView: View {
    var score: Double
    var body: some View {
        ZStack {
            Circle().trim(from: 0.15, to: 0.85)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle().trim(from: 0.15, to: 0.15 + 0.7 * score)
                .stroke(AngularGradient(colors: [.green, Theme.amber, .red], center: .center, startAngle: .degrees(0), endAngle: .degrees(252)),
                        style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.15), value: score)
            VStack(spacing: 4) {
                Text("\(Int(score * 100))").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.level(score))
                Text(label).font(.title3.bold()).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("مستوى الخطر \(Int(score * 100)) بالمية، \(label)")
    }
    var label: String { ScanStatus(score: score).title }
}

struct ScanView: View {
    @Environment(SensorEngine.self) private var engine
    @State private var feedback = FeedbackController()
    @AppStorage("sound") private var sound = true
    @AppStorage("haptics") private var haptics = true
    @State private var scanning = false
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !engine.available {
                        ContentUnavailableView("ما فيه حساس مغناطيس", systemImage: "xmark.octagon", description: Text("جهازك ما يدعم حساس المغناطيس"))
                    } else if engine.baselineMagnitude == nil {
                        CalibrateView()
                    } else {
                        statusBanner
                        GaugeView(score: scanning ? engine.score : 0).frame(height: 260)
                        scanHint
                        HStack(spacing: 12) {
                            metric("ذبذبة الكهربا", value: engine.humScore, detail: engine.humMeasurable ? (engine.humLikely ? "محتمل" : String(format: "×%.1f", engine.humRatio)) : "غير متاح", icon: "bolt.fill")
                            metric("حديد أو معدن", value: engine.magScore, detail: engine.metalLikely ? String(format: "%.0f µT محتمل", engine.magDeviation) : String(format: "%.0f µT", engine.magDeviation), icon: "square.grid.3x3.fill")
                        }
                        liveGraph
                        Button {
                            scanning.toggle()
                            if scanning { feedback.start() } else { feedback.stop() }
                        } label: {
                            Label(scanning ? "وقف الفحص" : "ابدأ الفحص", systemImage: scanning ? "stop.fill" : "play.fill")
                                .font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 18))
                        .tint(scanning ? .red : Theme.amber)
                        Button { scanning = false; feedback.stop(); engine.resetBaseline() } label: {
                            Label("أعد المعايرة", systemImage: "arrow.counterclockwise").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        if !engine.humMeasurable {
                            Label("سرعة حساس جوالك ما تسمح بقياس ذبذبة الكهربا بدقة، المؤشر الحين يعتمد على المعدن بس", systemImage: "info.circle.fill")
                                .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        Label("تنبيه صريح: تيّار أداة مساعدة تعتمد على حساس البوصلة في الجوال، مو جهاز كشف معتمد. يلقط السلك اللي يمشي فيه تيار قوي (شغّل جهاز يسحب كهربا مثل سخان أو استشوار)، وما يلقط السلك اللي ما عليه حمل. الحديد والمسامير تبان في مؤشر المعدن. افصل الكهربا من الطبلون دايماً قبل الخرم", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Label("التطبيق ينبهك بس. افصل الكهربا دايماً قبل الخرم", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
            .background(Theme.bg)
            .navigationTitle("تيّار")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHelp = true } label: { Label("كيف أستخدمه", systemImage: "questionmark.circle.fill").labelStyle(.titleAndIcon).font(.headline) }
                }
            }
            .sheet(isPresented: $showHelp) { HowToView() }
            .onAppear { engine.start() }
            .onDisappear { scanning = false; feedback.stop() }
            .onChange(of: engine.rawMagnitude) {
                guard scanning else { return }
                feedback.soundOn = sound; feedback.hapticsOn = haptics
                feedback.update(score: engine.score)
            }
        }
    }

    private var status: ScanStatus { ScanStatus(score: scanning ? engine.score : 0) }

    private var statusBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: scanning ? status.icon : "pause.circle.fill").font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text(scanning ? status.title : "الفحص واقف").font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                Text(scanning ? status.meaning : "اضغط ابدأ الفحص تحت وحط أعلى الجوال على الجدار").font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(scanning ? status.color : .secondary)
        .padding(16)
        .background((scanning ? status.color : .gray).opacity(0.18), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke((scanning ? status.color : .gray).opacity(0.6), lineWidth: 2))
        .animation(.easeOut(duration: 0.2), value: status)
        .accessibilityElement(children: .combine)
    }

    private var scanHint: some View {
        HStack(spacing: 14) {
            PhoneDiagram().frame(height: 110)
            VStack(alignment: .leading, spacing: 8) {
                Label("الصق أعلى الجوال على الجدار", systemImage: "arrow.up.circle.fill").font(.headline)
                Label("حركه ببطء يمين ويسار", systemImage: "arrow.left.and.right.circle.fill").font(.headline)
                Button("شوف الشرح بالصور") { showHelp = true }.font(.callout.bold())
            }
            .foregroundStyle(Theme.amber)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 20))
    }

    private var liveGraph: some View {
        VStack(alignment: .leading) {
            Text("المجال المغناطيسي مباشر").font(.headline)
            Chart(engine.history) { p in
                LineMark(x: .value("t", p.id), y: .value("µT", p.value)).foregroundStyle(Theme.amber)
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 120)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding().background(Theme.card, in: .rect(cornerRadius: 14))
    }

    private func metric(_ title: String, value: Double, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: scanning ? value : 0).tint(Theme.level(value))
            Text(detail).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding().frame(maxWidth: .infinity).background(Theme.card, in: .rect(cornerRadius: 14))
    }
}

struct CalibrateView: View {
    @Environment(SensorEngine.self) private var engine
    var body: some View {
        VStack(spacing: 20) {
            Text("الخطوة الأولى: المعايرة").font(.largeTitle.bold()).multilineTextAlignment(.center).padding(.top, 20)
            HStack(spacing: 16) {
                Image(systemName: "figure.stand").font(.system(size: 70))
                Image(systemName: "iphone").font(.system(size: 56)).foregroundStyle(Theme.amber)
                Image(systemName: "arrow.left.and.right").font(.title.bold())
                Text("١ متر").font(.title2.bold())
                Image(systemName: "rectangle.split.3x3").font(.system(size: 60)).foregroundStyle(.brown)
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
            Text("امسك الجوال بعيد عن الجدران والأجهزة والحديد بمسافة متر تقريباً، وخله ثابت لين تخلص المعايرة")
                .font(.title3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if engine.calibrating {
                ProgressView(value: engine.calibrationProgress).scaleEffect(y: 3).padding()
                Text("جاري المعايرة لا تحرك الجوال").font(.title3.bold()).foregroundStyle(Theme.amber)
            } else {
                Button { engine.beginCalibration() } label: {
                    Label("ابدأ المعايرة", systemImage: "scope").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 60)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 18))
            }
            Text(String(format: "سرعة القراءة: %.0f قراءة بالثانية", engine.rawRate)).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct TestModeView: View {
    @Environment(SensorEngine.self) private var engine
    var body: some View {
        NavigationStack {
            List {
                Section("سرعة الحساس الفعلية") {
                    row("المغناطيس الخام", String(format: "%.1f Hz", engine.rawRate))
                    row("حركة الجهاز المعايرة", String(format: "%.1f Hz", engine.motionRate))
                    row("تردد الكهربا يطلع عند", String(format: "%.1f Hz", engine.aliasFrequency))
                    if engine.rawRate > 0 && engine.rawRate < 30 {
                        Text("سرعة الحساس قليلة، كشف ذبذبة الكهربا غالباً ما بيشتغل على جوالك").foregroundStyle(.red).font(.footnote)
                    }
                }
                Section("القراءات") {
                    row("X", String(format: "%.1f µT", engine.rawField.x))
                    row("Y", String(format: "%.1f µT", engine.rawField.y))
                    row("Z", String(format: "%.1f µT", engine.rawField.z))
                    row("المجموع الخام", String(format: "%.1f µT", engine.rawMagnitude))
                    row("المجموع المعاير", String(format: "%.1f µT", engine.calibratedMagnitude))
                    row("دقة المعايرة", engine.calibrationAccuracy)
                    row("قوة الكهربا عند التردد", String(format: "%.4f", engine.bandPower))
                    row("نسبة الإشارة للضجيج", String(format: "%.1f dB (المعايرة %.1f)", engine.hfVariance, engine.baselineSNR))
                }
                Section {
                    Chart {
                        RectangleMark(xStart: .value("من", bandLo), xEnd: .value("إلى", bandHi))
                            .foregroundStyle(Theme.amber.opacity(0.15))
                        ForEach(engine.spectrum) { p in
                            LineMark(x: .value("Hz", p.freq), y: .value("قوة", log10(max(p.power, 1e-6))))
                                .foregroundStyle(Theme.amber)
                        }
                    }
                    .chartXAxisLabel("Hz")
                    .frame(height: 220)
                    .environment(\.layoutDirection, .leftToRight)
                } header: { Text("الطيف الترددي") } footer: {
                    Text("قرّب الجوال من سلك شغال (مثل سلك شاحن لابتوب أو مكيف شغال) وشوف هل يطلع ارتفاع في المنطقة الصفرا")
                }
            }
            .navigationTitle("وضع التجربة")
            .onAppear { engine.start() }
        }
    }
    private var bandLo: Double { engine.autoBand ? max(0, engine.aliasFrequency - 2) : engine.bandLow }
    private var bandHi: Double { engine.autoBand ? engine.aliasFrequency + 2 : engine.bandHigh }
    private func row(_ k: String, _ v: String) -> some View {
        LabeledContent(k) { Text(v).monospacedDigit() }
    }
}

struct SettingsView: View {
    @Environment(SensorEngine.self) private var engine
    @AppStorage("sound") private var sound = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("onboarded") private var onboarded = true
    @State private var showHelp = false
    var body: some View {
        @Bindable var e = engine
        NavigationStack {
            Form {
                Section("التنبيه") {
                    Toggle("الصوت", isOn: $sound)
                    Toggle("الرجة", isOn: $haptics)
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
                    Button("كيف أستخدمه") { showHelp = true }
                    Button("اعرض تنبيه السلامة مرة ثانية") { onboarded = false }
                } footer: {
                    Text("تيّار ينبهك بس وما يضمن إن المكان آمن. افصل الكهربا واستخدم جهاز كشف أسلاك حقيقي.")
                }
            }
            .navigationTitle("الإعدادات")
            .sheet(isPresented: $showHelp) { HowToView() }
        }
    }
}
