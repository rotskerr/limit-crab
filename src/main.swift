import Cocoa

struct Limit {
    var percent: Double; var resets: Date?; var wasReset = false
    /// Якщо час скидання вже минув, а свіжих даних нема — ліміт фактично скинувся (а не «досі 100%»).
    var live: Limit { if let r = resets, r < Date() { return Limit(percent: 0, resets: nil, wasReset: true) }; return self }
}
struct Usage { var session: Limit?; var weekly: Limit? }

// MARK: історія використання (той самий формат CSV, що й на Windows: "ISO-час;сесія;тиждень")
struct Sample { var t: Date; var s: Double?; var w: Double? }

enum History {
    static let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClaudeLimits")
    static let file = dir.appendingPathComponent("history.csv")
    static let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let isoPlain = ISO8601DateFormatter()
    static func iso(_ d: Date) -> String { isoFrac.string(from: d) }
    static func parse(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }
    static func add(_ t: Date, _ u: Usage) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func num(_ l: Limit?) -> String { l.map { String($0.percent) } ?? "" }
        let line = "\(iso(t));\(num(u.session));\(num(u.weekly))\n"
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(line.utf8))   // сучасний API: помилка диска не кладе програму
        } else { try? line.write(to: file, atomically: true, encoding: .utf8) }
        // файл > 600 КБ (≈50 днів): лишаємо останні 30 днів
        if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 600 * 1024 {
            let keep = load(since: t.addingTimeInterval(-30 * 86400)).map { "\(iso($0.t));\($0.s.map { String($0) } ?? "");\($0.w.map { String($0) } ?? "")" }
            try? (keep.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
    static func load(since: Date) -> [Sample] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var out: [Sample] = []
        for line in text.split(separator: "\n") {
            let p = line.split(separator: ";", omittingEmptySubsequences: false)
            guard p.count >= 3, let t = parse(String(p[0])), t >= since else { continue }
            out.append(Sample(t: t, s: Double(p[1]), w: Double(p[2])))
        }
        return out
    }
}

// Вікно з графіком: сесія і тиждень за 24 години або 7 днів. На кінці лінії сесії сидить краб.
final class GraphView: NSView {
    var data: [Sample] = []
    var week = false
    var hoverX: CGFloat = -1
    var tickFrame = 0
    var crabImage: ((Double?, Int) -> NSImage)?
    var plot = NSRect.zero, tabDay = NSRect.zero, tabWeek = NSRect.zero
    var timer: Timer?
    static let days = ["Нд", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]
    static let bg = App.c(32, 32, 32), gridC = App.c(58, 58, 58), textC = App.c(220, 220, 220), dim = App.c(140, 140, 140)
    static let sessionC = App.c(217, 120, 87), weekC = App.c(100, 170, 255)

    override var isFlipped: Bool { true }
    func start() {
        timer?.invalidate()
        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tickFrame += 1; self?.needsDisplay = true }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        hoverX = plot.contains(p) ? p.x : -1
    }
    override func mouseExited(with e: NSEvent) { hoverX = -1 }
    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if tabDay.contains(p) { week = false } else if tabWeek.contains(p) { week = true }
        needsDisplay = true
    }

    @discardableResult
    func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat = 11, color: NSColor, align: NSTextAlignment = .left, vcenter: Bool = false) -> NSSize {
        let str = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
        let sz = str.size()
        let px = align == .center ? x - sz.width / 2 : align == .right ? x - sz.width : x
        str.draw(at: NSPoint(x: px, y: vcenter ? y - sz.height / 2 : y))
        return sz
    }

    func chip(_ s: String, x: CGFloat, y: CGFloat, on: Bool) -> NSRect {
        let sz = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 13)]).size()
        let r = NSRect(x: x, y: y, width: sz.width + 20, height: sz.height + 10)
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        (on ? App.c(70, 70, 70) : GraphView.bg).setFill(); path.fill()
        (on ? App.c(70, 70, 70) : GraphView.gridC).setStroke(); path.lineWidth = 1; path.stroke()
        text(s, x: r.midX, y: r.midY, size: 13, color: on ? .white : GraphView.dim, align: .center, vcenter: true)
        return r
    }
    func legend(_ s: String, _ c: NSColor, right: CGFloat, cy: CGFloat) -> CGFloat {
        let w = text(s, x: right, y: cy, color: GraphView.textC, align: .right, vcenter: true).width
        let p = NSBezierPath(); p.move(to: NSPoint(x: right - w - 22, y: cy)); p.line(to: NSPoint(x: right - w - 6, y: cy))
        c.setStroke(); p.lineWidth = 3; p.stroke()
        return right - w - 22
    }

    override func draw(_ dirtyRect: NSRect) {
        let W = bounds.width, H = bounds.height, m: CGFloat = 16
        GraphView.bg.setFill(); bounds.fill()
        tabDay = chip("24 години", x: m, y: m, on: !week)
        tabWeek = chip("7 днів", x: tabDay.maxX + 8, y: m, on: week)
        let lx = legend("Тиждень", GraphView.weekC, right: W - m, cy: tabDay.midY)
        _ = legend("Сесія 5 год", GraphView.sessionC, right: lx - 16, cy: tabDay.midY)

        let top = tabDay.maxY + 20
        plot = NSRect(x: 52, y: top, width: W - 52 - 28, height: H - 34 - top)
        let to = Date(), from = to.addingTimeInterval(week ? -168 * 3600 : -24 * 3600)
        func X(_ t: Date) -> CGFloat { plot.minX + CGFloat(t.timeIntervalSince(from) / to.timeIntervalSince(from)) * plot.width }
        func Y(_ v: Double) -> CGFloat { plot.maxY - CGFloat(max(0, min(100, v)) / 100) * plot.height }

        // Сітка: 0–100% і вертикальні позначки часу
        GraphView.gridC.setStroke()
        for v in stride(from: 0, through: 100, by: 25) {
            let l = NSBezierPath(); l.lineWidth = 1
            l.move(to: NSPoint(x: plot.minX, y: Y(Double(v)))); l.line(to: NSPoint(x: plot.maxX, y: Y(Double(v)))); l.stroke()
            text("\(v)%", x: plot.minX - 6, y: Y(Double(v)), color: GraphView.dim, align: .right, vcenter: true)
        }
        let cal = Calendar.current
        var t: Date
        if week { t = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: from))! }
        else {
            let c = cal.dateComponents([.year, .month, .day, .hour], from: from)
            t = cal.date(byAdding: .hour, value: 3, to: cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour! - c.hour! % 3))!)!
        }
        while t < to {
            let x = X(t)
            GraphView.gridC.setStroke()
            let l = NSBezierPath(); l.lineWidth = 1; l.move(to: NSPoint(x: x, y: plot.minY)); l.line(to: NSPoint(x: x, y: plot.maxY)); l.stroke()
            let label: String
            if week { label = GraphView.days[cal.component(.weekday, from: t) - 1] + " \(cal.component(.day, from: t))" }
            else { label = String(format: "%02d:%02d", cal.component(.hour, from: t), cal.component(.minute, from: t)) }
            text(label, x: x, y: plot.maxY + 6, color: GraphView.dim, align: .center)
            t = cal.date(byAdding: week ? .day : .hour, value: week ? 1 : 3, to: t)!
        }
        for (v, c) in [(70.0, App.c(255, 159, 10)), (90.0, App.c(255, 69, 58))] {      // пороги 70% і 90%
            let l = NSBezierPath(); l.lineWidth = 1; l.setLineDash([4, 4], count: 2, phase: 0)
            l.move(to: NSPoint(x: plot.minX, y: Y(v))); l.line(to: NSPoint(x: plot.maxX, y: Y(v)))
            c.withAlphaComponent(0.43).setStroke(); l.stroke()
        }

        let pts = data.filter { $0.t >= from }
        if pts.isEmpty {
            let msg = "Історія тільки почала збиратися: нова точка з'являється з кожним оновленням (раз на 5 хв)."
            text(msg, x: plot.midX, y: plot.midY, size: 13, color: GraphView.dim, align: .center, vcenter: true)
            return
        }
        // Лінія з розривами там, де програма не працювала довше 20 хв; під сесією напівпрозора заливка.
        func series(_ val: (Sample) -> Double?, _ c: NSColor, fill: Bool) {
            var run: [NSPoint] = [], prev = Date.distantPast
            func flush() {
                if run.count > 1 {
                    if fill {
                        let poly = NSBezierPath(); poly.move(to: run[0]); run.dropFirst().forEach { poly.line(to: $0) }
                        poly.line(to: NSPoint(x: run.last!.x, y: plot.maxY)); poly.line(to: NSPoint(x: run[0].x, y: plot.maxY)); poly.close()
                        c.withAlphaComponent(0.18).setFill(); poly.fill()
                    }
                    let l = NSBezierPath(); l.lineWidth = 2; l.lineJoinStyle = .round
                    l.move(to: run[0]); run.dropFirst().forEach { l.line(to: $0) }
                    c.setStroke(); l.stroke()
                } else if run.count == 1 {
                    c.setFill(); NSBezierPath(ovalIn: NSRect(x: run[0].x - 2, y: run[0].y - 2, width: 4, height: 4)).fill()
                }
                run.removeAll()
            }
            for p in pts {
                guard let v = val(p) else { continue }
                if !run.isEmpty && p.t.timeIntervalSince(prev) > 20 * 60 { flush() }
                run.append(NSPoint(x: X(p.t), y: Y(v))); prev = p.t
            }
            flush()
        }
        series({ $0.w }, GraphView.weekC, fill: false)
        series({ $0.s }, GraphView.sessionC, fill: true)

        // Краб сидить на останній точці сесії й підстрибує
        if let last = pts.last(where: { $0.s != nil }), let make = crabImage {
            let k: CGFloat = 3
            let mood = max(last.s!, last.w ?? 0)
            let r = NSRect(x: X(last.t) - 6.5 * k, y: Y(last.s!) - 9 * k, width: 15 * k, height: 10 * k)
            NSGraphicsContext.current?.imageInterpolation = .none
            make(mood, tickFrame).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if hoverX >= 0 { readout(pts, X, Y) }
    }

    // Підказка під мишкою: найближча точка, її час і значення.
    func readout(_ pts: [Sample], _ X: (Date) -> CGFloat, _ Y: (Double) -> CGFloat) {
        guard let best = pts.min(by: { abs(X($0.t) - hoverX) < abs(X($1.t) - hoverX) }) else { return }
        let x = X(best.t)
        let l = NSBezierPath(); l.lineWidth = 1; l.move(to: NSPoint(x: x, y: plot.minY)); l.line(to: NSPoint(x: x, y: plot.maxY))
        App.c(120, 120, 120).setStroke(); l.stroke()
        if let w = best.w { GraphView.weekC.setFill(); NSBezierPath(ovalIn: NSRect(x: x - 4, y: Y(w) - 4, width: 8, height: 8)).fill() }
        if let s = best.s { GraphView.sessionC.setFill(); NSBezierPath(ovalIn: NSRect(x: x - 4, y: Y(s) - 4, width: 8, height: 8)).fill() }
        func fmt(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "—" }
        let cal = Calendar.current
        let msg = GraphView.days[cal.component(.weekday, from: best.t) - 1]
            + String(format: " %02d:%02d", cal.component(.hour, from: best.t), cal.component(.minute, from: best.t))
            + "\nсесія \(fmt(best.s)) · тиждень \(fmt(best.w))"
        let attr = NSAttributedString(string: msg, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: GraphView.textC])
        let sz = attr.boundingRect(with: NSSize(width: 1000, height: 1000), options: [.usesLineFragmentOrigin]).size
        let bw = sz.width + 16, bh = sz.height + 10
        let bx = x + 10 + bw > plot.maxX ? x - 10 - bw : x + 10
        let box = NSRect(x: bx, y: plot.minY + 6, width: bw, height: bh)
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        App.c(48, 48, 48).setFill(); path.fill(); App.c(80, 80, 80).setStroke(); path.lineWidth = 1; path.stroke()
        attr.draw(with: NSRect(x: box.minX + 8, y: box.minY + 5, width: sz.width + 2, height: sz.height + 2), options: [.usesLineFragmentOrigin])
    }
}

// Прозоре вікно на весь екран: краб, чайка, батут і слід у ньому — шари Core Animation. Рух шару (зміна frame) система
// композитить на відеочипі без перемальовування, тож 30 к/с коштують мало. Кліки проходять крізь вікно.
final class OverlayView: NSView {
    private var pool: [CALayer] = []
    private var poolImgs: [NSImage?] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()                 // layer-hosting: шари керуються вручну, AppKit нічого не малює
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
    func setItems(_ items: [(NSImage, NSRect)], scale: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)      // без вбудованих анімацій CA: рухаємо самі
        while pool.count < items.count {
            let l = CALayer(); l.magnificationFilter = .nearest; l.minificationFilter = .nearest
            layer?.addSublayer(l); pool.append(l); poolImgs.append(nil)
        }
        for (i, l) in pool.enumerated() {
            if i < items.count {
                let (img, r) = items[i]
                if poolImgs[i] !== img {                                      // та сама картинка — текстуру не перезавантажуємо
                    poolImgs[i] = img
                    l.contents = (img.representations.first as? NSBitmapImageRep)?.cgImage ?? img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
                if l.frame != r { l.frame = r }
                l.zPosition = CGFloat(i); l.contentsScale = scale; l.isHidden = false
            } else if !l.isHidden { l.isHidden = true; l.contents = nil; poolImgs[i] = nil }
        }
        CATransaction.commit()
    }
}
final class Overlay {
    let panel: NSPanel
    let view = OverlayView(frame: .zero)
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = view
    }
    func show(on scr: NSScreen, barBottom: CGFloat, items: [(NSImage, NSRect)]) {
        let fr = scr.frame                                                    // вікно не змінює розміру щокадру
        if panel.frame != fr { panel.setFrame(fr, display: false) }
        view.setItems(items.map { ($0.0, $0.1.offsetBy(dx: -fr.minX, dy: -fr.minY)) }, scale: scr.backingScaleFactor)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
    func hide() { if panel.isVisible { view.setItems([], scale: 2); panel.orderOut(nil) } }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var usage: Usage?
    var error: String?
    var updated: Date?
    var timer: Timer?

    func save() {
        guard let u = usage else { return }
        let d = UserDefaults.standard
        d.set(u.session?.percent, forKey: "sp"); d.set(u.session?.resets, forKey: "sr")
        d.set(u.weekly?.percent, forKey: "wp"); d.set(u.weekly?.resets, forKey: "wr")
        d.set(updated, forKey: "at")
    }
    func load() {
        let d = UserDefaults.standard
        if let na = d.object(forKey: "na") as? Date { nextAllowed = na }
        guard let at = d.object(forKey: "at") as? Date else { return }
        func lim(_ p: String, _ r: String) -> Limit? {
            guard let v = d.object(forKey: p) as? Double else { return nil }
            return Limit(percent: v, resets: d.object(forKey: r) as? Date)
        }
        usage = Usage(session: lim("sp", "sr"), weekly: lim("wp", "wr")); updated = at; stale = true
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.target = self
        item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        load()
        render()
        if let at = updated, Date().timeIntervalSince(at) < 300 { nextAllowed = at.addingTimeInterval(300) } else if Date() >= nextAllowed { refresh() }
        let anim = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(anim, forMode: .common)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        // ClaudeLimits --ask-access: показує системний запит на дозвіл «Універсальний доступ» і за 2 хв закривається.
        if CommandLine.arguments.contains("--ask-access") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.askAccess() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { NSApp.terminate(nil) }
        }
        // ClaudeLimits --dump-button out.png: зберігає те, що зараз намальовано в кнопці менюбару, і виходить (для діагностики).
        if let i = CommandLine.arguments.firstIndex(of: "--dump-button"), i + 1 < CommandLine.arguments.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let b = self?.item.button, let rep = b.bitmapImageRepForCachingDisplay(in: b.bounds) else { exit(1) }
                b.cacheDisplay(in: b.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                print("image=\(String(describing: b.image?.size)) title=\(b.attributedTitle.string) bounds=\(b.bounds) pos=\(b.imagePosition.rawValue)"); fflush(stdout)
                exit(0)
            }
        }
        if CommandLine.arguments.contains("--selftest") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.selftest() } }
        // ClaudeLimits --autoplay <сцена> --dump-overlay out.png: через 4 с малює шари оверлея в PNG (перевірка без дозволу на запис екрана).
        if let i = CommandLine.arguments.firstIndex(of: "--dump-overlay"), i + 1 < CommandLine.arguments.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let v = self?.overlay?.view, let root = v.layer, let scr = NSScreen.main else { print("оверлея нема"); exit(1) }
                let sc = scr.backingScaleFactor, w = Int(root.bounds.width * sc), h = Int(root.bounds.height * sc)
                guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
                ctx.setFillColor(CGColor(gray: 0.15, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.scaleBy(x: sc, y: sc)
                root.render(in: ctx)
                if let img = ctx.makeImage() { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
                print("шарів: \(root.sublayers?.filter { !$0.isHidden }.count ?? 0), рамки: \(root.sublayers?.filter { !$0.isHidden }.map { $0.frame } ?? [])"); fflush(stdout)
                exit(0)
            }
        }
        if CommandLine.arguments.contains("--wake-test") {
            DispatchQueue.global().async {
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                let before = self.tokenInfo()?.expires, t0 = Date()
                let code = self.wakeClaude(force: true)
                let after = self.tokenInfo()?.expires
                print("claude: \(App.claudePath() ?? "не знайдено") | код: \(code.map(String.init) ?? "—") за \(String(format: "%.1f", Date().timeIntervalSince(t0))) с | вхід до \(before.map(f.string) ?? "—") → \(after.map(f.string) ?? "—")")
                fflush(stdout); exit(0)
            }
        }
        // Для перевірки: ClaudeLimits --autoplay walk|gull запускає прогулянку чи чайку за 2 секунди після старту.
        if let i = CommandLine.arguments.firstIndex(of: "--autoplay"), i + 1 < CommandLine.arguments.count {
            let what = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if what == "walk" { self?.startWalk() } else if what == "gull" { self?.startGull() } else if what == "tramp" { _ = self?.startTramp() } else if what == "hide" { self?.startHide() } else if what == "snip" { _ = self?.startSnip() } else if what == "psycho" { self?.startPsycho() } else if what == "smash" { self?.startSmash() }
            }
        }
    }

    // MARK: data
    func token() -> String? { tokenInfo()?.token }
    // Токен і час, коли він спливає (expiresAt у мс). У Keychain нічого не пишемо: оновлює вхід лише сам Claude Code.
    func tokenInfo() -> (token: String, expires: Date?)? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let t = oauth["accessToken"] as? String else { return nil }
        let exp = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return (t, exp)
    }

    // Вхід Claude Code живе ≈8 год і оновлюється лише коли Claude Code запускається. Якщо вхід от-от спливе (або сервер дав 401),
    // краб тихо запускає `claude -p ok` на найдешевшій моделі (≈6 с, крихта ліміту), не частіше ніж раз на 30 хв. Як на Windows (PR №13).
    var lastWake = Date.distantPast
    static func claudePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for p in ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"] where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil                                                 // GUI-програма не бачить PATH із .zshrc, тож шукаємо у звичних місцях
    }
    /// Блокує поточний (фоновий) потік до ~60 с. Повертає код виходу або nil, якщо не запускали.
    @discardableResult
    func wakeClaude(force: Bool = false) -> Int32? {
        guard force || Date().timeIntervalSince(lastWake) > 30 * 60, let path = App.claudePath() else { return nil }
        lastWake = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-p", "ok", "--model", "haiku", "--no-session-persistence", "--strict-mcp-config"]
        p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(60)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        if p.isRunning { p.terminate(); return -1 }
        return p.terminationStatus
    }

    var nextAllowed = Date.distantPast
    var failures = 0
    var stale = false
    func refresh(retried: Bool = false) {
        if Date() < nextAllowed { render(); return }
        nextAllowed = Date().addingTimeInterval(30) // не частіше ніж раз на 30 с
        DispatchQueue.global().async {
            if let info = self.tokenInfo(), let exp = info.expires, exp.timeIntervalSinceNow < 120 { self.wakeClaude() }   // вхід от-от спливе
            guard let tok = self.token() else {
                DispatchQueue.main.async { self.error = "Не знайшов вхід у Claude Code"; self.render() }; return
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            URLSession.shared.dataTask(with: req) { data, resp, err in
                DispatchQueue.main.async {
                    if let err = err { self.error = "Немає мережі (\(err.localizedDescription))"; self.render(); return }
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 429 {
                        let ra = Double((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0
                        let backoff = min(300 * pow(2, Double(self.failures)), 1800)
                        self.failures += 1
                        self.nextAllowed = Date().addingTimeInterval(max(ra, backoff))
                        self.stale = true
                        self.error = nil
                        UserDefaults.standard.set(self.nextAllowed, forKey: "na")
                        self.render(); return
                    }
                    guard code == 200, let data = data,
                          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        if code == 401 && !retried {                                // вхід протермінувався: будимо Claude Code і пробуємо ще раз
                            DispatchQueue.global().async {
                                let woke = self.wakeClaude()
                                DispatchQueue.main.async {
                                    if woke == 0 { self.nextAllowed = .distantPast; self.refresh(retried: true) }
                                    else { self.error = "Вхід у Claude Code протермінувався: відкрий Claude Code"; self.render() }
                                }
                            }
                            return
                        }
                        self.error = code == 401 ? "Вхід у Claude Code протермінувався: відкрий Claude Code" : "Помилка \(code)"
                        self.render(); return
                    }
                    func parse(_ k: String) -> Limit? {
                        guard let d = j[k] as? [String: Any], let u = d["utilization"] as? Double else { return nil }
                        var date: Date?
                        if let s = d["resets_at"] as? String {
                            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
                        }
                        return Limit(percent: u, resets: date)
                    }
                    let before = self.usage?.session?.percent
                    self.usage = Usage(session: parse("five_hour"), weekly: parse("seven_day"))
                    if let b = before, let a = self.usage?.session?.percent, b - a >= 15 { self.celebrateUntil = self.frame + 100 }
                    self.error = nil; self.stale = false; self.failures = 0; self.updated = Date(); self.save(); self.render()
                    if let u = self.usage { History.add(self.updated!, u); self.graphView?.data = History.load(since: Date().addingTimeInterval(-8 * 86400)) }
                }
            }.resume()
        }
    }

    // MARK: ui
    func left(_ d: Date?) -> String {
        guard let d = d else { return "—" }
        let s = Int(d.timeIntervalSinceNow); if s <= 0 { return "зараз" }
        let days = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if days > 0 { return "\(days)д \(h)г" }
        if h > 0 { return "\(h)г \(m)хв" }
        return "\(m)хв"
    }

    func color(_ p: Double) -> NSColor { p >= 90 ? .systemRed : (p >= 70 ? .systemOrange : .labelColor) }

    // MARK: краб (маскот)
    // Піксельний краб 15×10 клітинок (клітинка = 2pt), анімований. Логіку й координати перенесено один в один із
    // Crab.Paint у windows/ClaudeLimits.cs (там полотно 14 завширшки, тут на 1 більше, щоб не різався хвіст рибки).
    // Витівок, що потребують руху по панелі (прогулянка, перетягування, чайка), на Mac поки немає.
    static let perMinute = 400                 // кадрів по 0.15 с
    var celebrateUntil = 0, waveUntil = 0, welcomeUntil = 0, coolUntil = 0
    var nextCool = 15 * App.perMinute          // окуляри: на 10 с раз на 15–30 хв
    var debugForce: String?                    // примусовий стан (дебаг-меню / --preview)
    var isHover = false, isLonely = false, lookDx = 0
    func menuWillOpen(_ menu: NSMenu) { waveUntil = frame + 18; menuOpen = true }   // клік по крабу: махає

    // MARK: прогулянка і чайка (прозоре вікно поверх менюбару)
    // Краб іноді йде ліворуч уздовж менюбару, роззирається, махає й повертається; раз на 40–90 хв під менюбаром
    // пролітає чайка: краб лякається, а коли вона пролетіла, сердиться їй услід. Логіка з TaskbarWidget у windows/ClaudeLimits.cs.
    var walkRest = 26, walkHide = false                           // кадрів на дальньому кінці; хованка в камері
    var walkStart = -1, walkDist = -1, walkOut = 0, walkPart = 1.0
    var gullStart = -1, gullFrom: CGFloat = 0, angryUntil = 0
    var isWalking = false, isScared = false
    var nextWalk = 25 * App.perMinute, nextGull = 45 * App.perMinute
    var menuOpen = false
    var overlay: Overlay?
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; item.menu = nil }

    static let gullFrames = [
        ["......K...", ".....WW...", "....WW....", "OHHBBBBBTT", "..BBBBB...", "..........", ".........."],
        ["..........", "..........", "..........", "OHHBWWWWWK", "..BBBBB...", "..........", ".........."],
        ["..........", "..........", "..........", "OHHBBBBBTT", "..BBBBB...", "....WW....", ".....K...."],
        ["..........", "..........", "..........", "OHHBWWWWWK", "..BBBBB...", "..........", ".........."]]
    static let flake: NSImage = {   // 3×3 pt, малюється один раз
        let i = NSImage(size: NSSize(width: 3, height: 3), flipped: false) { r in NSColor(white: 1, alpha: 0.9).setFill(); r.fill(); return true }
        return i
    }()
    static func monthDay() -> Int { let c = Calendar.current, n = Date(); return c.component(.month, from: n) * 100 + c.component(.day, from: n) }
    static func isWinter(force: String?) -> Bool { let md = monthDay(); return md >= 1215 || md <= 110 || force == "winter" }
    static func isHalloween(force: String?) -> Bool { let md = monthDay(); return (md >= 1025 && md <= 1101) || force == "halloween" }
    // Кажан: на Хелловін замість чайки
    static let batFrames = [
        ["W........W", "WW..EE..WW", "WWW.RR.WWW", ".WWBBBBWW.", "....BB...."],
        [".........." , ".........." , "WWW.EE.WWW", "WWWWBBWWWW", "..W.BB.W.."],
        [".........." , ".........." , "...EBBE...", "WWWBBBBWWW", "WWW.BB.WWW"],
        [".........." , ".........." , "WWW.EE.WWW", "WWWWBBWWWW", "..W.BB.W.."]]
    func batImage(_ f: Int) -> NSImage {
        let k: CGFloat = 3, rows = App.batFrames[(f / 2) % 4]
        let img = NSImage(size: NSSize(width: 10 * k, height: 7 * k), flipped: true) { _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    let c: NSColor? = ch == "W" ? App.c(95, 62, 120) : (ch == "B" || ch == "E") ? App.c(45, 30, 60) : ch == "R" ? App.c(255, 60, 60) : nil
                    if let c = c { c.setFill(); NSRect(x: CGFloat(x) * k, y: CGFloat(y + 1) * k, width: k, height: k).fill() }
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }
    func gullImage(_ f: Int) -> NSImage {
        if App.isHalloween(force: debugForce) { return batImage(f) }
        let k: CGFloat = 3, rows = App.gullFrames[(f / 2) % 4]
        let img = NSImage(size: NSSize(width: 10 * k, height: 7 * k), flipped: true) { _ in
            func cell(_ x: Int, _ y: Int, _ c: NSColor, h: CGFloat = 1, dy: CGFloat = 0) {
                c.setFill(); NSRect(x: CGFloat(x) * k, y: (CGFloat(y) + dy) * k, width: k, height: h * k).fill()
            }
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    switch ch {
                    case "O": cell(x, y, App.c(255, 159, 10), h: 0.5, dy: 0.3)           // дзьоб
                    case "H", "B": cell(x, y, .white)
                    case "W": cell(x, y, App.c(190, 195, 205))                           // крило
                    case "K": cell(x, y, App.c(50, 50, 55))                              // темний кінчик крила
                    case "T": cell(x, y, App.c(160, 165, 170), h: 0.6)                   // хвіст
                    default: break
                    }
                }
            }
            cell(1, 3, App.dark, h: 0.4, dy: 0.1)                                        // око
            return true
        }
        img.isTemplate = false
        return img
    }
    lazy var blankIcon = NSImage(size: NSSize(width: 30, height: 20))   // порожнє місце вдома, поки краб гуляє

    func canPlay() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        guard let p = shownPct, p < 90, hour >= 7, hour < 23, !menuOpen, !isLonely, walkStart < 0, gullStart < 0, tramp == nil, snip == nil, dragMode == .none, psycho == nil, smash == nil, !pressed else { return false }
        return item.button?.window?.occlusionState.contains(.visible) ?? false
    }
    func startWalk() {
        guard !homeHidden else { return }
        walkStart = frame; walkDist = -1; walkPart = 0.5 + Double.random(in: 0..<0.5); walkRest = 26; walkHide = false
    }
    func startGull() {
        guard gullStart < 0, let scr = item.button?.window?.screen ?? NSScreen.main else { return }
        gullStart = frame; gullFrom = scr.frame.maxX + 5
    }
    @objc func debugWalk() { startWalk() }
    @objc func debugGull() { startGull() }

    // MARK: ловити курсор, перетягування краба, меню по кліку
    struct Snip { var start = 0; var hx: CGFloat = 0, hy: CGFloat = 0, tx: CGFloat = 0, ty: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0 }
    var snip: Snip?

    func homeRect() -> NSRect? {
        guard let btn = item.button, let win = btn.window, let cell = btn.cell else { return nil }
        let ir = win.convertToScreen(btn.convert(cell.imageRect(forBounds: btn.bounds), to: nil))
        return NSRect(x: ir.minX, y: ir.minY, width: 30, height: 20)
    }

    // Сцена «ловить курсор»: краб стрибає до мишки, клацає клешнею біля неї (іскри) й стрибає назад. Мишку не рухає.
    func startSnip() -> Bool {
        guard !homeHidden, let r = homeRect(),
              let scr = item.button?.window?.screen ?? NSScreen.main else { return false }
        let m = NSEvent.mouseLocation
        guard scr.frame.contains(m), m.y < scr.frame.maxY - 150, hypot(m.x - r.midX, m.y - r.midY) > 200 else { return false }
        var s = Snip(start: frame)
        s.hx = r.midX; s.hy = r.minY + 2; s.cx = m.x; s.cy = m.y
        s.tx = max(scr.frame.minX + 20, m.x - 36); s.ty = max(scr.frame.minY + 4, m.y - 22)    // поруч, ліворуч-нижче від стрілки
        snip = s
        return true
    }
    @objc func debugSnip() { if !startSnip() { NSSound.beep() } }   // потрібно, щоб мишка була далеко від краба й не вгорі екрана
    func snipFrame(_ s: Snip, _ t0: Double) -> (x: CGFloat, y: CGFloat, pose: String, look: Int, spark: Bool)? {
        var t = t0
        if t < 14 { let u = CGFloat(t / 14); return (s.hx + (s.tx - s.hx) * u, s.hy + (s.ty - s.hy) * u + 120 * 4 * u * (1 - u), "fly", 0, false) }
        t -= 14
        if t < 22 { return (s.tx, s.ty, "snip", 1, true) }
        t -= 22
        if t < 16 { let u = CGFloat(t / 16); return (s.tx + (s.hx - s.tx) * u, s.ty + (s.hy - s.ty) * u + 100 * 4 * u * (1 - u), "fly", 0, false) }
        return nil
    }
    func sparkImage(_ f: Int) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { _ in
            App.c(255, 214, 10).setFill()
            if (f / 2) % 2 == 0 { NSRect(x: 5, y: 0, width: 2, height: 12).fill(); NSRect(x: 0, y: 5, width: 12, height: 2).fill() }
            else { for p in [(1, 1), (9, 1), (1, 9), (9, 9), (5, 5)] { NSRect(x: p.0, y: p.1, width: 2, height: 2).fill() } }
            return true
        }
    }

    // Перетягування: затисни краба й потягни: він у руці; відпусти (можна кинути): падає, відскакує, паморочиться й летить додому.
    // Клік без перетягування відкриває меню. Мишку читаємо опитуванням стану кнопки (під час кліку по статус-іконці події не доходять до монітора).
    enum DragMode { case none, held, fall, dizzy, holo, back }
    var dragMode = DragMode.none
    var pressed = false, sawDrag = false, pressScreen = NSPoint.zero, pressTimer: Timer?
    var grab = NSPoint.zero, dpos = NSPoint.zero, dvel = NSPoint.zero
    var bounces = 0, backStart = 0
    var dizzyUntil = 0.0, lastPhys = -1.0
    var floorY: CGFloat = 0, backFrom = NSPoint.zero
    var moveHist: [(Date, NSPoint)] = []
    var currentMenu: NSMenu?

    @objc func statusClicked(_ sender: Any?) {
        guard let e = NSApp.currentEvent else { openMenu(); return }
        if e.type == .rightMouseDown { openMenu(); return }
        pressed = true; sawDrag = false
        pressScreen = NSEvent.mouseLocation
        moveHist = [(Date(), pressScreen)]
        pressTimer?.invalidate()
        pressTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.pollPress() }
        RunLoop.main.add(pressTimer!, forMode: .common)
    }
    func openMenu() {
        render()                            // свіжий відлік «оновиться через …» на момент відкриття меню
        guard let btn = item.button, let m = currentMenu else { return }
        item.menu = m                       // меню чіпляємо лише на мить показу, щоб звичайний клік можна було перехопити
        btn.performClick(nil)
    }
    func pollPress() {
        let m = NSEvent.mouseLocation
        moveHist.append((Date(), m)); if moveHist.count > 8 { moveHist.removeFirst() }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            if dragMode == .none && !sawDrag && hypot(m.x - pressScreen.x, m.y - pressScreen.y) > 4,
               let r = homeRect(), r.contains(pressScreen), !homeHidden, !menuOpen {
                dragMode = .held; sawDrag = true
                grab = NSPoint(x: pressScreen.x - r.minX, y: pressScreen.y - r.minY)
                dpos = NSPoint(x: m.x - grab.x, y: m.y - grab.y)
            }
            if dragMode == .held { dpos = NSPoint(x: m.x - grab.x, y: m.y - grab.y); updatePlay() }   // плавно, між кадрами анімації
            return
        }
        pressTimer?.invalidate(); pressTimer = nil; pressed = false          // відпустили
        if dragMode == .held { releaseThrow() } else if !sawDrag { openMenu() }
    }
    func releaseThrow() {
        guard let scr = item.button?.window?.screen ?? NSScreen.main else { dragMode = .none; return }
        if let a = moveHist.first, let b = moveHist.last {                    // швидкість мишки в момент відпускання → кидок
            let dt = max(b.0.timeIntervalSince(a.0), 0.016)
            dvel = NSPoint(x: max(-50, min(50, (b.1.x - a.1.x) / CGFloat(dt) * 0.15 * 0.6)),
                           y: max(-50, min(50, (b.1.y - a.1.y) / CGFloat(dt) * 0.15 * 0.6)))
        }
        floorY = (dockInfo(scr)?.top ?? scr.frame.minY) - 2                   // падає на Dock (або на низ екрана)
        bounces = 0; lastPhys = -1.0; dragMode = .fall
    }
    // Фізика кидка за справжнім часом дрібними кроками (≤ 0.25 кадру): відскоки не залежать від частоти малювання.
    func stepFall(_ scr: NSScreen) {
        if lastPhys < 0 { lastPhys = ft }
        var remaining = ft - lastPhys
        lastPhys = ft
        while remaining > 1e-6 && dragMode == .fall {
            let h = CGFloat(min(0.25, remaining)); remaining -= Double(h)
            dvel.y -= 14 * h
            dpos.x += dvel.x * h; dpos.y += dvel.y * h
            if dpos.x < scr.frame.minX { dpos.x = scr.frame.minX; dvel.x = -dvel.x * 0.6 }
            if dpos.x + 30 > scr.frame.maxX { dpos.x = scr.frame.maxX - 30; dvel.x = -dvel.x * 0.6 }
            if dpos.y + 20 > scr.frame.maxY - 2 { dpos.y = scr.frame.maxY - 22; dvel.y = -abs(dvel.y) * 0.4 }
            if dpos.y <= floorY {
                dpos.y = floorY
                if abs(dvel.y) < 30 || bounces >= 2 { dragMode = .dizzy; dizzyUntil = ft + 20; dvel = .zero }
                else { dvel.y = -dvel.y * 0.5; dvel.x *= 0.7; bounces += 1 }
            }
        }
    }

    // Автотест кліку й перетягування: ClaudeLimits --selftest. Сам «натискає» мишкою (потрібен дозвіл «Універсальний доступ»), пише результат у stdout.
    func selftest() {
        func cg(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: NSScreen.screens[0].frame.height - p.y) }
        func post(_ t: CGEventType, _ p: NSPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: cg(p), mouseButton: .left)?.post(tap: .cghidEventTap) }
        func say(_ s: String) { print("[selftest] \(s)"); fflush(stdout) }
        guard AXIsProcessTrusted(), let r = homeRect(), let win = item.button?.window else { say("нема дозволу або кнопки"); exit(1) }
        let crab = NSPoint(x: r.midX, y: r.midY), text = NSPoint(x: win.frame.maxX - 20, y: win.frame.midY)
        func at(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
        at(0) { post(.mouseMoved, text) }
        at(0.3) { post(.leftMouseDown, text) }
        at(0.4) { post(.leftMouseUp, text) }
        at(1.2) { say("1) клік по тексту: меню \(self.menuOpen ? "ВІДКРИЛОСЬ ✓" : "НЕ відкрилось ✗")"); self.closeMenuForTest() }
        at(2.4) { post(.mouseMoved, crab) }
        at(2.6) { post(.leftMouseDown, crab) }
        for i in 1...12 { at(2.7 + 0.05 * Double(i)) { post(.leftMouseDragged, NSPoint(x: crab.x - 4 * CGFloat(i), y: crab.y - 22 * CGFloat(i))) } }
        at(3.5) { say("2) схопили й потягли: режим = \(self.dragMode) (очікую held)") }
        at(3.6) { post(.leftMouseUp, NSPoint(x: crab.x - 48, y: crab.y - 264)) }
        for k in 1...12 { at(3.6 + 0.6 * Double(k)) { say("   +\(String(format: "%.1f", 0.6 * Double(k))) с: \(self.dragMode) y=\(Int(self.dpos.y))") } }
        at(14) { say("3) після кидка: \(self.dragMode == .none ? "краб удома ✓" : "ще в русі ✗") (меню знову відкривається кліком: \(self.menuOpen ? "відкрите" : "закрите"))"); exit(0) }
    }
    func closeMenuForTest() {
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap) }   // Esc
    }

    // MARK: кіберпанк-режим (перенесено з Windows-версії)
    // Глітч від 95% (та сама цифра, що й настрій краба), кіберпсихоз із телепортами, неоновий краб зі світінням і слідом,
    // голограма-телепорт додому після кидка, танець з еквалайзером. Лише загальний стиль (неон, імпланти, глітч, голограми).
    var cyber = UserDefaults.standard.object(forKey: "cyber") as? Bool ?? true
    var forceBrokenUntil = 0, beamUntil = 0, holoStart = 0, nextPsycho = 400, lastTrailFrame = -1
    var beamAt = NSPoint.zero
    var trail: [NSPoint] = []
    var lastCrabImage: NSImage?
    var titleGlitched = false
    var trailKey = "", trailImgs: [NSImage] = []
    var lastIconBytes = Data(), lastIconBlank = false
    // Іконку в менюбарі малює окремий системний процес, і кожна зміна його будить. Більшість кадрів у спокої однакові
    // (краб підстрибує раз на 4–9 кадрів), тож однакові пікселі не відправляємо.
    func setIcon(_ img: NSImage) {
        guard let btn = item.button else { return }
        if img === blankIcon {
            if !lastIconBlank { btn.image = img; lastIconBlank = true; lastIconBytes = Data() }
            return
        }
        lastIconBlank = false
        if let rep = img.representations.first as? NSBitmapImageRep, let p = rep.bitmapData {
            let bytes = Data(bytesNoCopy: p, count: rep.bytesPerRow * rep.pixelsHigh, deallocator: .none)
            if bytes == lastIconBytes { return }
            lastIconBytes = Data(bytes)
        } else { lastIconBytes = Data() }
        btn.image = img
    }
    var lastTitle: NSAttributedString?
    var liveKey = ""
    var holoCache: NSImage?, holoCacheFrame = -1, eqCache: NSImage?, eqCacheFrame = -1
    static let logOn = CommandLine.arguments.contains("--log"), fpsOn = CommandLine.arguments.contains("--fps")
    var isDancing = false
    struct Psycho { var start = 0; var xs: [CGFloat] = []; var durs: [Int] = [] }
    var psycho: Psycho?

    // Поріг гліча: справжній найвищий з лімітів (у дебазі: вибраний рівень).
    var hotValue: Double? {
        if debugIndex != 0 { return App.debugStates[debugIndex].1 }
        return [usage?.session?.live.percent, usage?.weekly?.live.percent].compactMap { $0 }.max()
    }
    var glitchOn: Bool { cyber && ((hotValue ?? 0) >= 95 || psycho != nil || debugForce == "glitch") }

    static func lcg(_ s: Int) -> Int {                       // дешевий детермінований «випадковий» генератор
        var x = UInt64(bitPattern: Int64(s)) &* 6364136223846793005 &+ 1442695040888963407
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Int(x & 0x7fffffff)
    }
    func brokenFrame(_ f: Int) -> Bool { App.lcg(f &* 7919 &+ 17) % 100 < 45 }     // ~45% кадрів «зламані»

    func tinted(_ img: NSImage, _ c: NSColor, _ a: CGFloat) -> NSImage {
        NSImage(size: img.size, flipped: false) { r in img.draw(in: r); c.withAlphaComponent(a).setFill(); r.fill(using: .sourceAtop); return true }
    }
    func silhouette(_ img: NSImage, _ c: NSColor) -> NSImage {
        NSImage(size: img.size, flipped: false) { r in img.draw(in: r); c.setFill(); r.fill(using: .sourceIn); return true }
    }
    func faded(_ img: NSImage, _ a: CGFloat) -> NSImage {
        NSImage(size: img.size, flipped: false) { r in img.draw(in: r, from: .zero, operation: .sourceOver, fraction: a); return true }
    }
    // Рожеве неонове світіння: 4 копії краба, зсунуті на 1pt у 4 боки, під ним.
    func neonGlow(_ base: NSImage) -> NSImage {
        let g = silhouette(base, App.c(255, 41, 160))
        return NSImage(size: base.size, flipped: false) { r in
            for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                g.draw(in: r.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy)), from: .zero, operation: .sourceOver, fraction: 0.35)
            }
            base.draw(in: r)
            return true
        }
    }
    // Глітч: червона й бірюзова копії по боках, 4 горизонтальні смуги зі зсувом, биті пікселі; у 12% «зламаних» кадрів краб зникає.
    func glitched(_ base: NSImage, f: Int, forced: Bool) -> NSImage {
        guard forced || brokenFrame(f) else { return base }
        let seed = f &* 7919 &+ 17
        if App.lcg(seed &+ 1) % 100 < 12 { return NSImage(size: base.size) }
        let red = tinted(base, App.c(255, 38, 64), 0.75), cyan = tinted(base, App.c(0, 230, 255), 0.75)
        let w = base.size.width, h = base.size.height
        return NSImage(size: base.size, flipped: false) { _ in
            var st = seed
            func r(_ n: Int) -> Int { st = App.lcg(st &+ 1); return st % max(n, 1) }
            let sh = CGFloat(1 + r(2)) * 1.5
            red.draw(in: NSRect(x: -sh, y: 0, width: w, height: h))
            cyan.draw(in: NSRect(x: sh, y: 0, width: w, height: h))
            let bh = h / 4
            for b in 0..<4 {
                let dx = r(2) == 0 ? CGFloat(r(7) - 3) : 0
                base.draw(in: NSRect(x: dx, y: CGFloat(b) * bh, width: w, height: bh), from: NSRect(x: 0, y: CGFloat(b) * bh, width: w, height: bh), operation: .sourceOver, fraction: 1)
            }
            for _ in 0..<4 {
                (r(2) == 0 ? App.c(0, 230, 255) : App.c(255, 40, 160)).setFill()
                NSRect(x: CGFloat(r(Int(w) - 2)), y: CGFloat(r(Int(h) - 2)), width: 2, height: 2).fill()
            }
            return true
        }
    }
    // Голограма: синя напівпрозора копія зі стертими рядками, що повзуть; кожен 5-й кадр зникає.
    func hologram(_ base: NSImage, f: Int) -> NSImage? {
        if f % 5 == 4 { return nil }
        let blue = tinted(base, App.c(90, 205, 255), 0.75)
        return NSImage(size: base.size, flipped: false) { r in
            blue.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.6)
            var y = CGFloat((f * 2) % 3)
            while y < r.height { NSRect(x: 0, y: y, width: r.width, height: 1).fill(using: .clear); y += 3 }
            return true
        }
    }
    func beamImage() -> NSImage {                                  // промінь телепорту: бірюзова вертикальна смуга
        NSImage(size: NSSize(width: 4, height: 36), flipped: false) { r in App.c(0, 230, 255).withAlphaComponent(0.67).setFill(); r.fill(); return true }
    }
    // Неоновий еквалайзер під крабом: 7 стовпчиків, градієнт бірюзовий → рожевий, висять вниз від менюбару.
    func eqImage(level: CGFloat, f: Int) -> NSImage {
        let n = 7, bw: CGFloat = 3, gap: CGFloat = 1, maxH: CGFloat = 26
        return NSImage(size: NSSize(width: CGFloat(n) * (bw + gap), height: maxH), flipped: true) { _ in
            for i in 0..<n {
                let k = 0.45 + 0.8 * abs(sin(Double(f) / 2 + Double(i)))
                let u = CGFloat(i) / CGFloat(n - 1)
                NSColor(srgbRed: u, green: 0.9 - 0.7 * u, blue: 1 - 0.37 * u, alpha: 0.47).setFill()
                NSRect(x: CGFloat(i) * (bw + gap), y: 0, width: bw, height: min(maxH, level * CGFloat(k) * maxH)).fill()
            }
            return true
        }
    }
    // Кіберпсихоз: 5–7 телепортів у випадкові місця вільної частини менюбару (по 4–8 кадрів), останній: додому на 3 кадри.
    func startPsycho() {
        guard !homeHidden, smash == nil, let r = homeRect(), let scr = item.button?.window?.screen ?? NSScreen.main else { return }
        var p = Psycho(); p.start = frame
        let nt = notch(scr)
        // Вільні зони менюбару: на екранах із вирізом дві (праворуч від нього й ліворуч, над меню застосунків), інакше одна.
        var zones: [(CGFloat, CGFloat)] = []
        if let n = nt {
            zones.append((n.right + 8, r.minX))
            zones.append((scr.frame.minX + 240, n.left - 40))
        } else { zones.append((scr.frame.minX + 560, r.minX)) }
        zones = zones.filter { $0.1 > $0.0 + 10 }
        for _ in 0..<Int.random(in: 5...7) {
            let z = zones.randomElement() ?? (r.minX - 60, r.minX)
            p.xs.append(CGFloat.random(in: z.0...z.1)); p.durs.append(Int.random(in: 4...8))
        }
        p.xs.append(r.minX); p.durs.append(3)
        psycho = p
    }
    @objc func debugPsycho() { startPsycho() }
    @objc func toggleCyber() { cyber.toggle(); UserDefaults.standard.set(cyber, forKey: "cyber"); trail.removeAll(); render() }

    // Складений краб: база + неонове світіння + глітч.
    // Образи, що малюються кодом (drawingHandler), перемальовуються при кожному показі, а неонове світіння малює краба ще 8 разів.
    // Тому готовий образ один раз перетворюємо на растр (2 пікселі на pt), і далі показ майже безкоштовний.
    func rasterize(_ img: NSImage, scale: CGFloat = 2) -> NSImage {
        let w = max(1, Int(img.size.width * scale)), h = max(1, Int(img.size.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return img }
        rep.size = img.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .none
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: img.size)
        out.addRepresentation(rep)
        return out
    }
    var spriteCache: [String: NSImage] = [:]
    func cachedSprite(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let c = spriteCache[key] { return c }
        let i = rasterize(make()); spriteCache[key] = i; return i
    }
    var mascotCache: [String: NSImage] = [:], mascotCacheFrame = -1
    func mascot(_ pct: Double?, frame f: Int) -> NSImage {
        // Анімація краба покадрова, тож між кроками (швидкий таймер) перевикористовуємо ту саму картинку: економить процесор.
        if mascotCacheFrame != f { mascotCache.removeAll(); mascotCacheFrame = f }
        let key = "\(pct ?? -1)|\(playPose ?? "")|\(isWalking)|\(lookDx)|\(isScared)|\(isHover)|\(isLonely)|\(isDancing)|\(debugForce ?? "")|\(cyber)|\(glitchOn)|\(f < forceBrokenUntil)|\(rock)|\(smash?.start ?? -1)|\(tramp != nil)"
        if let c = mascotCache[key] { return c }
        var img = rasterize(mascotBase(pct, frame: f))
        if cyber { img = rasterize(neonGlow(img)) }
        if glitchOn { let g = glitched(img, f: f, forced: f < forceBrokenUntil); if g !== img { img = rasterize(g) } }
        mascotCache[key] = img
        return img
    }
    // Цифри в «зламаних» кадрах: неонові й смикаються по вертикалі.
    func glitchTitle() -> NSAttributedString? {
        guard let t = lastTitle else { return nil }
        let m = NSMutableAttributedString(attributedString: t), r = NSRange(location: 0, length: m.length)
        m.addAttribute(.foregroundColor, value: frame % 2 == 0 ? App.c(0, 230, 255) : App.c(255, 40, 160), range: r)
        m.addAttribute(.baselineOffset, value: CGFloat(App.lcg(frame &* 31) % 5 - 2), range: r)
        return m
    }

    // MARK: режим рок-зірки 🎸
    // Ірокез і електрогітара; іноді соло (б'є по струнах, кричить, нотки); від 75% хедбенг; від 95% раз на 2–5 хв розбиває гітару
    // (замах → удар → уламки → нова гітара); свято скидання ліміту — піротехніка; батут у Dock стає стейдж-дайвом (підсилювач, натовп з руками).
    var rock = UserDefaults.standard.object(forKey: "rock") as? Bool ?? true
    struct Smash { var start = 0 }
    var smash: Smash?
    var nextSmash = 700
    func startSmash() { guard smash == nil, psycho == nil, !homeHidden else { return }; smash = Smash(start: frame) }
    @objc func debugSmash() { startSmash() }
    @objc func toggleRock() { rock.toggle(); UserDefaults.standard.set(rock, forKey: "rock"); render() }
    func ampImage() -> NSImage {                                    // підсилювач замість батута (13×4 клітинки по 3 pt)
        let k: CGFloat = 3
        let img = NSImage(size: NSSize(width: 13 * k, height: 4 * k), flipped: true) { _ in
            func cell(_ x: Int, _ y: CGFloat, _ c: NSColor, h: CGFloat = 1) { c.setFill(); NSRect(x: CGFloat(x) * k, y: y * k, width: k, height: h * k).fill() }
            for x in 0..<13 { cell(x, 0, App.c(70, 70, 76), h: 0.6) }                                   // верхня кромка
            for y in 1...3 { for x in 0..<13 { cell(x, CGFloat(y), (x + y) % 2 == 0 ? App.c(26, 26, 28) : App.c(50, 50, 56)) } }   // решітка
            for x in [1, 3, 5] { cell(x, 0, App.c(235, 190, 60), h: 0.5) }                                // ручки
            return true
        }
        img.isTemplate = false
        return img
    }
    func handsImage(_ f: Int) -> NSImage {                          // натовп під крабом: руки вгору
        NSImage(size: NSSize(width: 30, height: 10), flipped: false) { _ in
            App.c(240, 200, 170).setFill()
            for i in 0..<5 {
                let x = CGFloat(3 + i * 6), hgt: CGFloat = (f / 2 + i) % 2 == 0 ? 7 : 9
                NSRect(x: x, y: 0, width: 2, height: hgt).fill(); NSRect(x: x - 0.5, y: hgt - 1, width: 3, height: 2).fill()
            }
            return true
        }
    }
    func debrisImage(_ k: Int) -> NSImage {                         // уламки гітари
        let c = [App.c(220, 30, 45), App.c(120, 78, 40), App.c(205, 210, 220)][k % 3]
        return NSImage(size: NSSize(width: 3, height: 3), flipped: false) { r in c.setFill(); r.fill(); return true }
    }

    // MARK: Dock і батут
    // Краб стрибає з менюбару вниз на Dock, відскакує від батута, іде до випадкової іконки програми, сідає на неї, а потім
    // батут запускає його назад у менюбар. Точні позиції іконок дає Універсальний доступ (потрібен дозвіл); без нього
    // позиції рахуються приблизно за розміром Dock.
    struct DockInfo { var top: CGFloat; var icons: [(x: CGFloat, top: CGFloat)]; var exact: Bool }
    struct Tramp { var start = 0; var hx: CGFloat = 0, hy: CGFloat = 0, tx: CGFloat = 0, dockTop: CGFloat = 0
                   var ix: CGFloat = 0, iconTop: CGFloat = 0; var walk = 0 }
    var tramp: Tramp?
    var playPose: String?                          // "fall" / "fly": поза краба на сцені
    var homeHidden: Bool { walkStart >= 0 || tramp != nil || snip != nil || dragMode != .none || psycho != nil }

    func dockInfo(_ scr: NSScreen) -> DockInfo? {
        let d = UserDefaults(suiteName: "com.apple.dock")
        let dockH = scr.visibleFrame.minY - scr.frame.minY
        guard (d?.string(forKey: "orientation") ?? "bottom") == "bottom", !(d?.bool(forKey: "autohide") ?? false), dockH > 20 else { return nil }
        let top = scr.visibleFrame.minY
        if AXIsProcessTrusted(), let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXChildrenAttribute as CFString, &ref) == .success, let kids = ref as? [AXUIElement] {
                for list in kids {
                    var role: CFTypeRef?; AXUIElementCopyAttributeValue(list, kAXRoleAttribute as CFString, &role)
                    var ch: CFTypeRef?
                    guard (role as? String) == "AXList", AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &ch) == .success,
                          let items = ch as? [AXUIElement] else { continue }
                    var icons: [(x: CGFloat, top: CGFloat)] = []
                    for it in items {
                        var sub: CFTypeRef?, pv: CFTypeRef?, sv: CFTypeRef?
                        AXUIElementCopyAttributeValue(it, kAXSubroleAttribute as CFString, &sub)
                        guard (sub as? String) == "AXApplicationDockItem" else { continue }
                        AXUIElementCopyAttributeValue(it, kAXPositionAttribute as CFString, &pv)
                        AXUIElementCopyAttributeValue(it, kAXSizeAttribute as CFString, &sv)
                        var p = CGPoint.zero, sz = CGSize.zero
                        guard let pv = pv, let sv = sv, CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID(),
                              AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &sz) else { continue }
                        icons.append((x: p.x + sz.width / 2, top: NSScreen.screens[0].frame.height - p.y))   // у координатах Cocoa (y вгору)
                    }
                    if !icons.isEmpty { return DockInfo(top: max(top, icons.map { $0.top }.max()!), icons: icons, exact: true) }   // край Dock = верх найвищої іконки
                }
            }
        }
        // Запасний варіант: Dock по центру, іконки з однаковим кроком (приблизно).
        let ts = d?.double(forKey: "tilesize") ?? 0, tile = CGFloat(ts > 0 ? ts : 48)
        let apps = (d?.array(forKey: "persistent-apps") ?? []).count
        let total = apps + 1 + (d?.array(forKey: "persistent-others") ?? []).count + 1
        guard apps > 0 else { return nil }
        let pitch = tile * 1.1, left = scr.frame.midX - CGFloat(total) * pitch / 2
        return DockInfo(top: top, icons: (0..<apps).map { (x: left + (CGFloat($0) + 0.5) * pitch, top: top - 8) }, exact: false)
    }

    func startTramp() -> Bool {
        guard !homeHidden, gullStart < 0, let btn = item.button, let win = btn.window, let cell = btn.cell,
              let scr = win.screen ?? NSScreen.main, let dock = dockInfo(scr), let icon = dock.icons.randomElement() else { return false }
        let ir = win.convertToScreen(btn.convert(cell.imageRect(forBounds: btn.bounds), to: nil))
        let xs = dock.icons.map { $0.x }
        var tx = icon.x + CGFloat.random(in: 120...300) * (Bool.random() ? 1 : -1)         // батут стоїть осторонь від іконки
        tx = min(max(tx, xs.min()! - 20), xs.max()! + 20)
        if abs(tx - icon.x) < 90 { tx = icon.x + (tx < icon.x ? -120 : 120) }
        var t = Tramp(start: frame)
        t.hx = ir.minX + 15; t.hy = ir.minY + 2; t.tx = tx; t.dockTop = dock.top; t.ix = icon.x; t.iconTop = min(icon.top, dock.top)
        t.walk = max(8, Int(abs(t.ix - tx) / 4))
        tramp = t
        if App.logOn { print("tramp exact=\(dock.exact) dockTop=\(dock.top) icons=\(dock.icons.count) tx=\(tx) ix=\(icon.x) iconTop=\(icon.top)"); fflush(stdout) }
        return true
    }
    @objc func debugTramp() { if !startTramp() { NSSound.beep() } }

    // Де краб на сцені з батутом у кадр t: центр X, нога Y (вгору), поза, чи йде, куди дивиться, чи прогнувся батут. nil — сцена скінчилась.
    func trampFrame(_ s: Tramp, _ t0: Double) -> (x: CGFloat, y: CGFloat, pose: String?, walking: Bool, look: Int, squash: Bool)? {
        var t = t0                                                               // дробові кадри: плавний рух між кроками анімації
        let g = s.dockTop + 11                                                   // верх батута
        let n1 = 12.0
        if t < n1 { let u = CGFloat(t / n1); return (s.hx + (s.tx - s.hx) * u, s.hy - (s.hy - g) * u * u, "fall", false, 0, false) }
        t -= n1
        for (dur, h) in zip([10.0, 8, 6, 4], [CGFloat(170), 100, 55, 25]) {     // відскоки, щоразу нижчі
            if t < dur { let u = CGFloat(t / dur); return (s.tx, g + h * 4 * u * (1 - u), "fly", false, 0, t < 1) }
            t -= dur
        }
        let dir = s.ix < s.tx ? -1 : 1, w = Double(s.walk)
        if t < w { let u = CGFloat(t / w); return (s.tx + (s.ix - s.tx) * u, s.dockTop, nil, true, dir, false) }
        t -= w
        if t < 6 { let u = CGFloat(t / 6); return (s.ix, s.dockTop + (s.iconTop - s.dockTop) * u + 18 * 4 * u * (1 - u), nil, false, 0, false) }   // застрибує на іконку
        t -= 6
        let sit = 240.0
        if t < sit { let k = Int(t / 25) % 4; return (s.ix, s.iconTop, nil, false, k == 1 ? -1 : k == 3 ? 1 : 0, false) }   // сидить, роззирається
        t -= sit
        if t < 5 { let u = CGFloat(t / 5); return (s.ix, s.iconTop + (s.dockTop - s.iconTop) * u + 12 * 4 * u * (1 - u), nil, false, 0, false) }
        t -= 5
        if t < w { let u = CGFloat(t / w); return (s.ix + (s.tx - s.ix) * u, s.dockTop, nil, true, -dir, false) }
        t -= w
        for (dur, h) in zip([6.0, 8], [CGFloat(20), 40]) {                      // розгойдується перед стартом
            if t < dur { let u = CGFloat(t / dur); return (s.tx, g + h * 4 * u * (1 - u), "fly", false, 0, t < 1) }
            t -= dur
        }
        let fl = 20.0                                                            // запуск назад у менюбар
        if t < fl { let u = CGFloat(t / fl); return (s.tx + (s.hx - s.tx) * u, g + (s.hy - g) * u + 130 * 4 * u * (1 - u), "fly", false, 0, false) }
        return nil
    }

    func trampolineImage(squash: Bool) -> NSImage {
        let k: CGFloat = 3
        let img = NSImage(size: NSSize(width: 13 * k, height: 4 * k), flipped: true) { _ in
            func cell(_ x: Int, _ y: CGFloat, _ c: NSColor, h: CGFloat = 1) { c.setFill(); NSRect(x: CGFloat(x) * k, y: y * k, width: k, height: h * k).fill() }
            for x in 0..<13 {                                                    // мат прогинається посередині, коли на нього приземлились
                let sag: CGFloat = squash ? (3...9 ~= x ? 0.7 : 0.3) : 0
                cell(x, sag, App.c(60, 110, 230), h: 0.5)
            }
            cell(0, 0, App.c(255, 59, 48), h: 0.5); cell(12, 0, App.c(255, 59, 48), h: 0.5)         // червоні краї
            for x in [1, 6, 11] { for y in 1...3 { cell(x, CGFloat(y), App.c(130, 130, 140)) } }    // ніжки
            return true
        }
        img.isTemplate = false
        return img
    }

    // Один раз на кілька хвилин вибирає, що робити: просто погуляти, сховатися в камері чи стрибнути на батут.
    func pickScene() {
        let hasNotch = (item.button?.window?.screen ?? NSScreen.main).flatMap { notch($0) } != nil
        let r = Int.random(in: 0..<20)
        if r < 8 { startWalk() }
        else if r < 11 && hasNotch { startHide() }
        else if r < 15 { if !startTramp() { startWalk() } }
        else if !startSnip() { startWalk() }
    }
    func startHide() {
        guard !homeHidden else { return }
        walkStart = frame; walkDist = -1; walkPart = 1; walkRest = 45; walkHide = true
    }
    @objc func debugHide() { startHide() }

    // Дозвіл «Універсальний доступ»: без нього точні позиції іконок Dock невідомі (краб сідає приблизно).
    @objc func askAccess() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    // Виріз камери (notch): X-межі вирізу на екрані або nil, якщо його нема. Пікселів там нема, тож краб не має туди заходити.
    func notch(_ scr: NSScreen) -> (left: CGFloat, right: CGFloat)? {
        guard scr.safeAreaInsets.top > 0, let l = scr.auxiliaryTopLeftArea, let r = scr.auxiliaryTopRightArea else { return nil }
        return (l.maxX, r.minX)
    }

    // Рахує, де зараз краб на прогулянці й чайка; повертає, що малювати поверх менюбару.
    func updatePlay() {
        isWalking = false; isScared = false; playPose = nil
        guard let btn = item.button, let win = btn.window, let cell = btn.cell else { return }
        let ir = win.convertToScreen(btn.convert(cell.imageRect(forBounds: btn.bounds), to: nil))
        let homeX = ir.minX, homeY = ir.minY
        guard let scr = win.screen ?? NSScreen.main else { return }
        var items: [(NSImage, NSRect)] = []
        var crabRect: NSRect?, crabImg: NSImage?

        if walkStart >= 0 {
            if walkDist < 0 {                                                       // перший кадр: рахуємо маршрут
                // Куди йти: до правого краю меню застосунків; на екранах із вирізом ще й за нього (краб огинає виріз знизу).
                let bound = notch(scr).map { $0.left - 60 } ?? (scr.frame.minX + 560)
                let farthest = max(0, homeX - bound)
                if walkHide, let n = notch(scr) { walkDist = max(60, Int(homeX - ((n.left + n.right) / 2 - 15))) }   // ховається за камерою
                else { walkDist = max(60, Int(farthest * CGFloat(walkPart))) }
                walkOut = max(10, walkDist / 4)                                     // 2 клітинки (4pt) за кадр
            }
            let t = ft - Double(walkStart)
            let wo = Double(walkOut), wr = Double(walkRest), wd = Double(walkDist)
            if t >= 2 * wo + wr { walkStart = -1; walkDist = -1 }
            else {
                let d = t < wo ? wd * t / wo : t < wo + wr ? wd : wd * (2 * wo + wr - t) / wo
                isWalking = t < wo || t >= wo + wr
                lookDx = t < wo ? -1 : t >= wo + wr ? 1 : (Int(t / 5) % 2 == 0 ? 1 : -1)
                isHover = false
                if !walkHide && t >= wo + wr / 2 && t < wo + wr { waveUntil = max(waveUntil, frame + 1) }   // махає
                // Біля вирізу камери краб обходить його впритул: зістрибує з правого боку, іде під ним і вилазить на лівий.
                var drop: CGFloat = 0
                if !walkHide, let n = notch(scr) {
                    let x = homeX - CGFloat(d)
                    let enter = min(max((n.right + 8 - x) / 8, 0), 1)             // наближається до вирізу справа
                    let leave = min(max((x + 30 - (n.left - 8)) / 8, 0), 1)       // ще не пройшов повз виріз ліворуч
                    drop = 30 * min(enter, leave)
                }
                let ci = mascot(shownPct, frame: frame); crabImg = ci
                crabRect = NSRect(x: homeX - CGFloat(d), y: homeY - drop, width: 30, height: 20); items.append((ci, crabRect!))
            }
        }
        if let tr = tramp {
            if let fr = trampFrame(tr, ft - Double(tr.start)) {
                playPose = fr.pose; isWalking = fr.walking; lookDx = fr.look; isHover = false
                if rock { items.append((cachedSprite("amp") { ampImage() }, NSRect(x: tr.tx - 19.5, y: tr.dockTop, width: 39, height: 12))) }      // рок: підсилювач
                else { items.append((cachedSprite("t\(fr.squash)") { trampolineImage(squash: fr.squash) }, NSRect(x: tr.tx - 19.5, y: tr.dockTop, width: 39, height: 12))) }
                let surf: CGFloat = rock && fr.walking ? 7 : 0                         // рок: пливе по натовпу над іконками
                if surf > 0 { items.append((cachedSprite("hands\((frame / 2) % 2)") { handsImage(frame) }, NSRect(x: fr.x - 15, y: tr.dockTop - 2, width: 30, height: 10))) }
                let ci = mascot(shownPct, frame: frame); crabImg = ci
                crabRect = NSRect(x: fr.x - 15, y: fr.y - 2 + surf, width: 30, height: 20); items.append((ci, crabRect!))
            } else { tramp = nil }
        }
        if let sn = snip {
            if let fr = snipFrame(sn, ft - Double(sn.start)) {
                playPose = fr.pose; lookDx = fr.look; isHover = false
                let ci = mascot(shownPct, frame: frame); crabImg = ci
                crabRect = NSRect(x: fr.x - 15, y: fr.y - 2, width: 30, height: 20); items.append((ci, crabRect!))
                if fr.spark { items.append((cachedSprite("s\((frame / 2) % 2)") { sparkImage(frame) }, NSRect(x: sn.cx - 4, y: sn.cy - 10, width: 12, height: 12))) }
            } else { snip = nil }
        }
        if let ps = psycho {                                                       // кіберпсихоз: серія телепортів із променем
            let t = ft - Double(ps.start)
            var acc = 0.0, idx = 0
            while idx < ps.durs.count && t >= acc + Double(ps.durs[idx]) { acc += Double(ps.durs[idx]); idx += 1 }
            if idx >= ps.durs.count { psycho = nil }
            else {
                let local = t - acc, x = ps.xs[idx], isLast = idx == ps.durs.count - 1
                playPose = "psycho"; isHover = false
                if local < 1 { forceBrokenUntil = max(forceBrokenUntil, frame + 1); items.append((cachedSprite("beam") { beamImage() }, NSRect(x: x + 13, y: homeY, width: 4, height: 36))) }
                if isLast || local < Double(ps.durs[idx]) - 1 {                            // перед стрибком на мить зникає
                    let ci = mascot(shownPct, frame: frame); crabImg = ci
                    crabRect = NSRect(x: x, y: homeY, width: 30, height: 20); items.append((ci, crabRect!))
                }
            }
        }
        if let sm = smash {                                                         // рок: уламки розбитої гітари розлітаються
            let t = ft - Double(sm.start)
            if t >= 40 { smash = nil }
            else if t >= 6 && t < 30 {
                let tau = CGFloat(t - 6), ox = homeX + 24, oy = homeY + 6
                for i in 0..<8 {
                    let vx = CGFloat(App.lcg(sm.start &* 13 &+ i) % 13 - 6) * 0.9, vy = CGFloat(App.lcg(sm.start &* 17 &+ i &* 7) % 8 + 3)
                    items.append((cachedSprite("deb\(i % 3)") { debrisImage(i % 3) }, NSRect(x: ox + vx * tau, y: oy + vy * tau - 0.6 * tau * tau, width: 3, height: 3)))
                }
            }
        }
        if dragMode != .none {
            isHover = false
            switch dragMode {
            case .fall: stepFall(scr); isWalking = true; playPose = "held"
            case .held: isWalking = true; playPose = "held"
            case .dizzy:
                playPose = "dizzy"
                if ft >= dizzyUntil {
                    if cyber { dragMode = .holo; holoStart = frame }                      // кібер: голограма, а не політ
                    else { dragMode = .back; backStart = frame; backFrom = dpos }
                }
            case .holo:
                playPose = "dizzy"
                if ft - Double(holoStart) >= 10 { dragMode = .none; beamUntil = frame + 2; beamAt = NSPoint(x: homeX, y: homeY); forceBrokenUntil = frame + 1 }
            default: break
            }
            if dragMode == .back {
                let u = min(CGFloat(ft - Double(backStart)) / 20, 1)
                dpos = NSPoint(x: backFrom.x + (homeX - backFrom.x) * u, y: backFrom.y + (homeY - backFrom.y) * u + 100 * 4 * u * (1 - u))
                playPose = "fly"
                if u >= 1 { dragMode = .none }
            }
            if dragMode == .holo {
                if holoCacheFrame != frame { holoCacheFrame = frame; holoCache = hologram(rasterize(mascotBase(shownPct, frame: frame)), f: frame - holoStart).map { rasterize($0) } }
                if let h = holoCache { items.append((h, NSRect(x: dpos.x, y: dpos.y, width: 30, height: 20))) }
            } else if dragMode != .none {
                let ci = mascot(shownPct, frame: frame); crabImg = ci
                crabRect = NSRect(x: dpos.x, y: dpos.y, width: 30, height: 20); items.append((ci, crabRect!))
            }
        }
        if gullStart >= 0 {
            let t = ft - Double(gullStart), gk: CGFloat = 3
            let gx = gullFrom - CGFloat(t) * 4 * gk
            let gy = win.frame.minY + 4 - 7 * gk + CGFloat(sin(t / 2) * 3)  // летить просто під менюбаром, погойдуючись
            let gc = gx + 5 * gk, cc = homeX + 15
            if gc < cc - 40 { angryUntil = frame + 22 } else if gc - cc < 160 { isScared = true }
            if gx + 10 * gk < scr.frame.minX { gullStart = -1 }
            items.append((cachedSprite("g\((frame / 2) % 4)\(App.isHalloween(force: debugForce))") { gullImage(frame) }, NSRect(x: gx, y: gy, width: 10 * gk, height: 7 * gk)))
        }
        // Неоновий слід (кібер): поки краб рухається, запам'ятовуємо позиції (до 6, кожні ≥6pt); удома слід тане по одній на кадр.
        if cyber {
            if let cr = crabRect {
                if let l = trail.last { if hypot(cr.minX - l.x, cr.minY - l.y) >= 6 { trail.append(cr.origin) } } else { trail.append(cr.origin) }
                if trail.count > 6 { trail.removeFirst() }
                lastCrabImage = crabImg
            } else if !trail.isEmpty && lastTrailFrame != frame { trail.removeFirst(); lastTrailFrame = frame }
            if !trail.isEmpty, let ci = lastCrabImage {
                let key = "\(frame)|\(trail.count)"
                if trailKey != key {
                    trailKey = key
                    let sil = silhouette(ci, App.c(0, 230, 255))
                    trailImgs = (0..<trail.count).map { rasterize(faded(sil, 0.06 + 0.25 * CGFloat($0) / CGFloat(max(trail.count - 1, 1)))) }
                }
                for (i, p) in trail.enumerated() where p != crabRect?.origin && i < trailImgs.count {
                    items.insert((trailImgs[i], NSRect(origin: p, size: NSSize(width: 30, height: 20))), at: 0)
                }
            }
        } else if !trail.isEmpty { trail.removeAll() }
        if frame < beamUntil { items.append((cachedSprite("beam") { beamImage() }, NSRect(x: beamAt.x + 13, y: beamAt.y, width: 4, height: 36))) }          // промінь телепорту додому
        if cyber && isDancing && !homeHidden {                                                                                         // еквалайзер під крабом
            if eqCacheFrame != frame { eqCacheFrame = frame; eqCache = rasterize(eqImage(level: 0.5 + 0.5 * CGFloat(sin(Double(frame) / 3)), f: frame)) }
            if let e = eqCache { items.append((e, NSRect(x: homeX - 3, y: win.frame.minY - 26, width: 28, height: 26))) }
        }
        if App.logOn && frame % 10 == 0 {
            print("panel=\(overlay?.panel.frame as Any) screens=\(NSScreen.screens.map { $0.frame })")
            print("f=\(frame) screen=\(scr.frame) bar=\(win.frame) home=(\(homeX),\(homeY)) walk=\(walkStart >= 0 ? "t=\(frame - walkStart) dist=\(walkDist) out=\(walkOut) walking=\(isWalking)" : "-") gull=\(gullStart >= 0 ? "t=\(frame - gullStart) scared=\(isScared) angry=\(frame < angryUntil)" : "-") items=\(items.map { $0.1 })")
            fflush(stdout)
        }
        if !items.isEmpty && App.isWinter(force: debugForce) {                          // узимку під час сцен іде сніг
            let W = max(1, Int(scr.frame.width)), H = max(1, Int(scr.frame.height))
            for i in 0..<36 {
                let x = scr.frame.minX + CGFloat((i * 197) % W) + CGFloat(sin((ft + Double(i * 7)) / 6) * 10)
                let y = scr.frame.maxY - CGFloat((Int(ft * 7) + i * 61) % H)
                items.insert((cachedSprite("flake") { App.flake }, NSRect(x: x, y: y, width: 3, height: 3)), at: 0)
            }
        }
        if items.isEmpty { overlay?.hide() }
        else {
            if overlay == nil { overlay = Overlay() }
            overlay?.show(on: scr, barBottom: win.frame.minY, items: items)
        }
    }

    func mascotBase(_ pct: Double?, frame f: Int) -> NSImage {
        let cyberOn = cyber
        let px: CGFloat = 2
        let p = pct ?? 0
        let force = debugForce
        let cal = Calendar.current, now = Date()
        let hour = cal.component(.hour, from: now), minute = cal.component(.minute, from: now)
        let dow = cal.component(.weekday, from: now) - 1               // 0 = неділя, 1 = понеділок, 5 = п'ятниця
        let md = cal.component(.month, from: now) * 100 + cal.component(.day, from: now)
        let hm = hour * 100 + minute
        let winter = md >= 1215 || md <= 110 || force == "winter"
        let halloween = (md >= 1025 && md <= 1101) || force == "halloween"
        let fall = playPose == "fall" || force == "fall"
        let fly = playPose == "fly" || force == "fly"
        let held = playPose == "held" || force == "held"
        let dizzy = playPose == "dizzy" || force == "dizzy"
        let snipP = playPose == "snip" || force == "snip"
        let psychoP = playPose == "psycho" || force == "psycho"
        let dance = (isDancing || force == "dance") && !fall && !fly && !held && !dizzy && !snipP && !psychoP
        let posed = fall || fly || held || dizzy || snipP || psychoP || dance
        let valentine = md == 214 || force == "valentine"
        let flagDay = md == 824 || md == 628 || force == "flag"            // День Незалежності / День Конституції
        let scared = !posed && (isScared || force == "scared")                                // чайка над головою
        let welcome = !scared && (f < welcomeUntil || force == "welcome")
        let angry = !scared && !welcome && (f < angryUntil || force == "angry")  // чайка щойно пролетіла
        let party = !scared && !welcome && !angry && (f < celebrateUntil || force == "party")
        let wave = !scared && !welcome && !angry && !party && (f < waveUntil || force == "wave")
        let special = posed || scared || welcome || angry || party || wave
        // Уночі спить, але не тоді, коли в дебаг-меню вибрано інший стан.
        let night = force == nil ? (hour < 7 || hour >= 23) : force == "sleep"
        let sleeping = !special && !isWalking && pct != nil && p < 75 && night
        let panic = !special && p >= 95
        let chill = !special && !sleeping && pct != nil && p < 90      // у доброму настрої для витівок
        let lonely = chill && !isWalking && (isLonely || force == "lonely")
        let fun = chill && !lonely                                       // ти поруч, можна пустувати
        let shades = fun && (f < coolUntil || force == "shades")
        let coffee = fun && p < 75 && !isWalking && (force == nil ? hour >= 8 && hour < 10 : force == "coffee")
        let lunch = fun && !isWalking && (force == nil ? hm >= 1300 && hm < 1330 : force == "lunch")
        let disco = fun && (force == nil ? dow == 5 && hour >= 17 && hour < 20 : force == "disco")
        let monday = fun && (force == nil ? dow == 1 && hour >= 8 && hour < 11 : force == "monday")
        let hover = fun && (isHover || force == "hover")

        let rockOn = rock
        let smashT: Int? = smash.map { f - $0.start }                     // «розбиває гітару»: кадр від початку сцени
        let lift = rockOn && (smashT.map { $0 < 6 } ?? false)             // замах: гітара над головою
        let smashing = rockOn && (smashT.map { $0 >= 6 && $0 < 8 } ?? false)
        let noGuitar = rockOn && (smashT.map { $0 >= 8 && $0 < 30 } ?? false)
        let rage = lift || smashing || noGuitar
        let onStage = tramp != nil && !isWalking && playPose == nil       // сидить на іконці під час стейдж-дайву
        let riff = rockOn && !rage && ((fun && (f % 120 < 16 || onStage)) || force == "riff")   // соло: раз на ~18 с на 2.4 с
        let headbang = rockOn && !rage && ((!special && !sleeping && pct != nil && p >= 75 && p < 90) || force == "headbang")
        let pyro = rockOn && party
        let bodyColor = p >= 90 ? App.c(204, 92, 77) : p >= 75 ? App.c(224, 128, 77) : App.c(217, 120, 87)
        let bobPeriod = party || hover || disco || welcome ? 2 : sleeping || lonely || monday ? 9 : p >= 90 ? 7 : p >= 75 ? 2 : p >= 50 ? 5 : 4
        let y0 = scared ? 4 : dance ? 3 + ((f / 2) % 2 == 0 ? 0 : 1) : posed ? 3 : headbang ? 3 + f % 2 : 3 + ((f / bobPeriod) % 2 == 0 ? 0 : 1)                // тіло починається з 3-го рядка
        let blink = f % (p >= 50 ? 36 : 24) < 2
        let legs = (f / (isWalking ? 1 : party || disco ? 2 : 3)) % 2 == 1 ? ".X..X.X..X." : "..X.X.X.X.."
        let rows = ["..XXXXXXX..", "..XXXXXXX..", "XXXXXXXXXXX", "XXXXXXXXXXX", "..XXXXXXX.."]
        let ox = 1 + (panic || scared || psychoP || smashing ? (f % 2 == 0 ? 1 : -1) : disco || dance ? ((f / 3) % 2 == 0 ? 1 : -1) : 0)   // тремтить або танцює
        let look = lookDx

        let img = NSImage(size: NSSize(width: 15 * px, height: 10 * px), flipped: true) { _ in
            let dark = App.dark
            func cell(_ x: Int, _ y: Int, _ c: NSColor, h: CGFloat = 1, dy: CGFloat = 0, fixed: Bool = false) {
                c.setFill()
                NSRect(x: CGFloat(x + (fixed ? 1 : ox)) * px, y: (CGFloat(y) + dy) * px, width: px, height: h * px).fill()
            }
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" { cell(x, y + y0, bodyColor) }
            }
            for (x, ch) in legs.enumerated() where ch == "X" { cell(x, 5 + y0, bodyColor) }
            let ey = 1 + y0, my = 3 + y0
            if cyberOn {                                                                     // неоновий імплант і хромовані кінчики клешень
                cell(2, ey, (f / 10) % 2 == 0 ? App.c(0, 230, 255) : App.c(0, 140, 200), h: 0.5, dy: 0.25)
                cell(0, y0 + 2, App.c(205, 210, 220), h: 0.5, dy: 0.25); cell(10, y0 + 2, App.c(205, 210, 220), h: 0.5, dy: 0.25)
            }
            let gRed = App.c(220, 30, 45), gWood = App.c(120, 78, 40)
            if rockOn && !noGuitar && !lift && !smashing {                                 // електрогітара в клешнях
                let sy: CGFloat = riff && f % 2 == 0 ? 0.5 : 0                             // б'є по струнах
                cell(1, y0 + 3, gRed, dy: sy); cell(2, y0 + 3, gRed, dy: sy)
                cell(1, y0 + 4, gRed, h: 0.7, dy: sy); cell(2, y0 + 4, gRed, h: 0.7, dy: sy)
                cell(2, y0 + 3, .white, h: 0.3, dy: 0.35 + sy)                             // накладка
                for x in 3...9 { cell(x, y0 + 2, gWood, h: 0.4, dy: 0.5) }                 // гриф
                cell(10, y0 + 1, dark); cell(10, y0 + 2, dark, h: 0.6)                     // голова грифа
                if riff { cell(3, y0 + 3, App.c(255, 214, 10), h: 0.5, dy: f % 2 == 0 ? 0 : 0.4) }   // медіатор
            }
            if lift {                                                                      // замах: гітара над головою
                cell(4, y0 - 2, gRed); cell(5, y0 - 2, gRed); cell(4, y0 - 1, gRed, h: 0.6); cell(5, y0 - 1, gRed, h: 0.6)
                cell(5, y0 - 3, gWood)
            }
            if smashing { cell(11, y0 + 4, gRed); cell(12, y0 + 4, gRed); cell(11, y0 + 5, gRed, h: 0.6) }   // удар об підлогу
            func eyes(_ dx: Int, _ closed: Bool) {
                if closed { cell(3 + dx, ey, dark, h: 0.4, dy: 0.6); cell(7 + dx, ey, dark, h: 0.4, dy: 0.6) }
                else { cell(3 + dx, ey, dark); cell(7 + dx, ey, dark) }
            }
            func happyEyes() { cell(3, ey, dark, h: 0.5); cell(7, ey, dark, h: 0.5) }          // ^ ^
            func wideEyes() { cell(2, ey, .white); cell(3, ey, dark); cell(6, ey, .white); cell(7, ey, dark) }
            func smile() { cell(5, my, dark, h: 0.5, dy: 0.2) }
            func drop(_ x: Int) { cell(x, 3 + (f / 2 + x) % 5, App.teal, fixed: true) }
            func claws(_ l: Bool, _ r: Bool) {                                                  // підняті клешні
                if l { cell(0, y0 + 1, bodyColor); cell((f / 2) % 2 == 0 ? 0 : -1, y0, bodyColor) }
                if r { cell(10, y0 + 1, bodyColor); cell((f / 2) % 2 == 0 ? 10 : 11, y0, bodyColor) }
            }
            var hat = halloween || winter

            if rage {                                          // розбиває гітару: злі брови, крик
                cell(2, y0, dark, h: 0.4, dy: 0.1); cell(3, y0, dark, h: 0.4, dy: 0.5); cell(6, y0, dark, h: 0.4, dy: 0.5); cell(7, y0, dark, h: 0.4, dy: 0.1)
                eyes(0, false); cell(5, my, dark)
                if lift { claws(true, true) } else if noGuitar { claws((f / 2) % 2 == 0, (f / 2) % 2 == 1) }   // «коза» по черзі
            } else if held {                                   // у руці: очі круглі, рот «о», ноги бовтаються
                wideEyes(); cell(5, my, dark)
            } else if dizzy {                                  // паморочиться: очі заплющені, зірочки кружляють
                eyes(0, true)
                cell(4, my, dark, h: 0.3, dy: 0.5); cell(5, my, dark, h: 0.3, dy: 0.2); cell(6, my, dark, h: 0.3, dy: 0.5)
                let sx = [1, 5, 9, 5], sy = [-1, -2, -1, 0]
                for i in 0..<2 { let j = (f / 2 + i * 2) % 4; cell(sx[j], y0 + sy[j] - 1, App.c(255, 214, 10), h: 0.6) }
            } else if snipP {                                  // клацає клешнею біля курсора
                eyes(1, false); smile()
                if (f / 2) % 2 == 0 { claws(false, true) }
            } else if fall {                                   // падає: очі круглі, рот «о», клешні вгору
                wideEyes(); cell(5, my, dark); claws(true, true)
            } else if fly {                                    // летить на батуті: радіє, клешні вгору
                happyEyes(); smile(); claws(true, true)
            } else if psychoP {                                // кіберпсихоз: паніка
                wideEyes(); cell(5, my, dark); drop(11); drop(0)
            } else if dance {                                  // танцює під музику: «^ ^», клешні по черзі
                happyEyes(); smile(); claws((f / 2) % 2 == 0, (f / 2) % 2 == 1)
            } else if scared {                                 // чайка над головою: присів, тремтить, клешні вгору, піт
                wideEyes(); cell(5, my, dark)
                claws(true, true); drop(11)
            } else if welcome {                                // повернувся! махає обома клешнями, над головою сердечко
                happyEyes(); cell(4, my, dark, h: 0.5, dy: 0.2); smile(); cell(6, my, dark, h: 0.5, dy: 0.2)
                claws(true, true)
                cell(1, ey + 1, App.blush, h: 0.5); cell(9, ey + 1, App.blush, h: 0.5)
                if !hat && (f / 3) % 2 == 0 {
                    cell(4, y0 - 2, App.heart); cell(6, y0 - 2, App.heart); cell(5, y0 - 1, App.heart)
                    cell(4, y0 - 1, App.heart, h: 0.5); cell(6, y0 - 1, App.heart, h: 0.5)
                }
            } else if angry {                                  // насуплені брови, дивиться вслід чайці, трясе клешнею
                eyes(-1, false)
                cell(2, y0, dark, h: 0.4, dy: 0.1); cell(3, y0, dark, h: 0.4, dy: 0.5)
                cell(6, y0, dark, h: 0.4, dy: 0.5); cell(7, y0, dark, h: 0.4, dy: 0.1)
                cell(4, my, dark, h: 0.3, dy: 0.4); cell(5, my, dark, h: 0.3, dy: 0.4); cell(6, my, dark, h: 0.3, dy: 0.4)
                claws(false, true)
            } else if party {
                happyEyes(); smile()
                if pyro {                                      // рок: піротехніка з боків, «коза»
                    for (x, ph) in [(0, 0), (12, 2)] {
                        let hgt = 3 + (f + ph) % 4
                        for k in 0..<hgt { cell(x, 9 - k, k < hgt / 2 ? App.c(255, 210, 40) : App.c(255, 110, 20), fixed: true) }
                        if (f + ph) % 3 == 0 { cell(x, 9 - hgt - 1, .white, h: 0.5, fixed: true) }
                    }
                    claws(true, true)
                } else {
                    for i in 0..<6 {                           // конфеті падає
                        cell((i * 5 + 2) % 13 - 1, (f / 2 + i * 2) % 9, App.confetti[i % 5], fixed: true)
                    }
                }
            } else if wave {
                happyEyes(); smile()
                if (f / 2) % 2 == 0 { cell(10, y0 + 1, bodyColor); cell(10, y0, bodyColor) }   // права клешня вгору
                else { cell(10, y0 + 1, bodyColor); cell(11, y0, bodyColor) }                   // і похитує
            } else if pct == nil {
                eyes(0, true)
            } else if sleeping {
                eyes(0, true)
                for z in 0...((f / 6) % 4) where z < 3 {       // zzz піднімається
                    cell(9 + z, 2 - z % 2 - (z == 2 ? 1 : 0), App.zzz, fixed: true)
                }
            } else if panic {
                wideEyes(); cell(5, my, dark)                  // очі з білками, рот «о»
                drop(11); drop(0)
            } else if p >= 90 {
                eyes(0, true); cell(5, my, dark, h: 0.5, dy: 0.3)
                drop(11); drop(0)
            } else if lonely {                                 // сумує: дрімає, іноді визирає тебе, сумний рот, сльозинка
                let t = f % 60
                if t < 12 { eyes((f / 4) % 2 == 0 ? -1 : 1, false) } else { eyes(0, true) }
                cell(4, my, dark, h: 0.3, dy: 0.5); cell(5, my, dark, h: 0.3, dy: 0.2); cell(6, my, dark, h: 0.3, dy: 0.5)
                if t >= 20 && t < 41 { cell(3, ey + 1 + (t - 20) / 7, App.teal, h: 0.5) }
            } else {
                if shades {                                    // темні окуляри
                    cell(3, ey, dark); cell(4, ey, dark); cell(6, ey, dark); cell(7, ey, dark)
                    cell(5, ey, dark, h: 0.4)
                    cell(3, ey, App.glint, h: 0.3); cell(6, ey, App.glint, h: 0.3)               // відблиск
                } else if disco || hover || riff { happyEyes() }
                else if headbang { eyes(0, true) }
                else if p >= 75 { eyes([-1, 0, 1, 0][(f / 4) % 4], blink) }
                else if monday { eyes(0, f % 50 >= 8 || f % 50 < 2) }                           // ледве розплющує очі
                else if coffee && f % 40 < 6 { eyes(0, true) }                                   // смакує ковток
                else { eyes(look, blink) }                                                       // дивиться за мишкою

                if monday && f % 50 < 8 { cell(5, my, dark) }                                    // позіхає
                else if lunch { cell(5, my, dark, h: (f / 3) % 2 == 0 ? 0.6 : 0.25, dy: 0.2) }   // жує
                else if riff || headbang { cell(5, my, dark, h: 0.8) }                          // кричить
                else if p >= 75 { drop(11) }
                else if p >= 50 || hover || shades || disco { smile() }
                if monday {                                                                      // мішки під очима
                    let bag = NSColor(srgbRed: 0.75 * 217 / 255, green: 0.75 * 120 / 255, blue: 0.75 * 87 / 255, alpha: 1)
                    cell(3, ey + 1, bag, h: 0.3); cell(7, ey + 1, bag, h: 0.3)
                }
                if hover { cell(1, ey + 1, App.blush, h: 0.5); cell(9, ey + 1, App.blush, h: 0.5) }   // червоніє
                if coffee {                                                                      // кружка в правій клешні
                    cell(11, y0 + 1, App.coffee, h: 0.5, dy: 0.5); cell(12, y0 + 1, App.coffee, h: 0.5, dy: 0.5)
                    for yy in 2...3 { cell(11, y0 + yy, App.mug); cell(12, y0 + yy, App.mug) }
                    cell(11 + (f / 4) % 2, y0 - (f / 4) % 3, App.steam, h: 0.5)                  // пара піднімається
                } else if lunch {                                                                // рибка в клешні
                    cell(11, y0 + 2, App.fish); cell(12, y0 + 2, App.fish, h: 0.6, dy: 0.2)
                    cell(13, y0 + 1, App.fish, h: 0.6, dy: 0.4); cell(13, y0 + 2, App.fish, h: 0.6, dy: 0.4)   // хвіст
                    cell(11, y0 + 2, dark, h: 0.3, dy: 0.2)                                      // око рибки
                }
                if disco {                                                                       // дзеркальна куля й вогники
                    hat = false
                    cell(5, y0 - 3, App.c(120, 120, 120), h: 0.5, dy: 0.5, fixed: true)          // ниточка
                    for x in 4...6 {                                                             // куля 3×2, грані блищать по черзі
                        for y in (y0 - 2)...(y0 - 1) {
                            cell(x, y, (x + y + f / 2) % 3 == 0 ? .white : App.c(150, 155, 170), fixed: true)
                        }
                    }
                    let lx = [0, 12, 1, 11, 6], ly = [1, 2, 8, 9, 0]
                    for i in 0..<lx.count where (f / 2 + i) % 3 != 0 {
                        cell(lx[i], ly[i], App.confetti[(f / 2 + i) % 5], h: 0.5, fixed: true)
                    }
                    claws((f / 3) % 2 == 0, (f / 3) % 2 == 1)
                }
            }
            if halloween && hat {                                                                // гарбуз на голові
                for x in 3...7 { cell(x, y0 - 1, App.pumpkin) }
                for x in 4...6 { cell(x, y0 - 2, App.pumpkin) }
                cell(4, y0 - 1, dark, h: 0.5); cell(6, y0 - 1, dark, h: 0.5)                     // вирізані очі
                cell(5, y0 - 3, App.stem)
            } else if winter && hat {                                                            // новорічна шапка
                for x in 3...7 { cell(x, y0 - 1, .white) }
                for x in 4...6 { cell(x, y0 - 2, App.red) }
                cell(5, y0 - 3, .white)
            }
            if rockOn && !hat && !disco && !lift && !flagDay && !(valentine && fun) {            // ірокез (при хедбенгу метляється)
                let hx = headbang ? (f % 2 == 0 ? -1 : 1) : 0, pink = App.c(255, 40, 160)
                cell(5 + hx, y0 - 1, dark); cell(4 + hx, y0 - 1, dark, h: 0.5, dy: 0.5); cell(6 + hx, y0 - 1, dark, h: 0.5, dy: 0.5)
                cell(5 + hx, y0 - 2, pink); cell(5 + hx * 2, y0 - 3, pink, h: 0.6, dy: 0.4)
            }
            if riff {                                                                            // нотки вилітають
                for i in 0..<2 { let k = (f / 2 + i * 3) % 6; cell(12 + i, 6 - k, App.c(255, 214, 10), h: 0.6, fixed: true) }
            }
            if flagDay && !hat {                                                                 // синьо-жовтий прапорець
                for y in (y0 - 3)...(y0 - 1) { cell(5, y, App.c(150, 150, 150)) }
                cell(6, y0 - 3, App.c(0, 87, 184)); cell(7, y0 - 3, App.c(0, 87, 184))
                cell(6, y0 - 2, App.c(255, 213, 0)); cell(7, y0 - 2, App.c(255, 213, 0))
            }
            if valentine && fun && !hat && (f / 4) % 2 == 0 {                                    // Валентинка: сердечка над головою
                cell(4, y0 - 2, App.heart); cell(6, y0 - 2, App.heart); cell(5, y0 - 1, App.heart)
                cell(4, y0 - 1, App.heart, h: 0.5); cell(6, y0 - 1, App.heart, h: 0.5)
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    static func c(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
    static let dark = c(31, 31, 31), teal = c(64, 200, 224), red = c(255, 59, 48), zzz = c(191, 191, 191)
    static let pumpkin = c(255, 140, 0), stem = c(52, 199, 89), blush = c(255, 105, 120)
    static let mug = c(240, 240, 240), coffee = c(111, 78, 55), steam = c(170, 170, 170), glint = c(110, 110, 110)
    static let fish = c(150, 185, 210), heart = c(255, 77, 109)
    static let confetti = [c(255, 204, 0), c(255, 45, 85), c(64, 200, 224), c(52, 199, 89), c(175, 82, 222)]

    var top: Double?
    var frame = 0
    // Плавність (як у Windows-версії): анімація краба (ноги, очі) йде кроками по 0.15 с, а рух по сценах і фізика кидка рахуються від
    // дробового часу `ft` = кадр + частка до наступного кадру. Швидкий таймер на 30 Гц працює лише поки краб рухається (`busy`).
    var lastFrameTime = Date()
    var ft: Double { Double(frame) + min(Date().timeIntervalSince(lastFrameTime) / 0.15, 1.0) }
    var fpsCount = 0, fpsT0 = Date()
    var busy: Bool {
        walkStart >= 0 || tramp != nil || snip != nil || psycho != nil || gullStart >= 0 || (dragMode != .none && dragMode != .held)
            || (cyber && isDancing) || !trail.isEmpty || frame < beamUntil || smash != nil
    }
    var fastTimer: Timer?
    // Швидкий таймер існує лише поки краб рухається: удома він не будить процесор 30 разів на секунду.
    func ensureFastTimer() {
        if busy, fastTimer == nil {
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.fastTick() }
            t.tolerance = 0.005
            RunLoop.main.add(t, forMode: .common); fastTimer = t
        }
    }
    func fastTick() {
        guard busy else { fastTimer?.invalidate(); fastTimer = nil; return }
        updatePlay()
        if App.fpsOn {
            fpsCount += 1
            if Date().timeIntervalSince(fpsT0) >= 1 { print("[fps] updatePlay: \(fpsCount)/с"); fflush(stdout); fpsCount = 0; fpsT0 = Date() }
        }
    }
    // Дебаг: примусово показати певний стан краба (0 = реальні дані)
    var debugIndex = 0
    static let debugStates: [(String, Double?, String?)] = [
        ("Авто (реальні дані)", nil, nil),
        ("Бадьорий · 20%", 20, nil),
        ("Спокійний · 60%", 60, nil),
        ("Стурбований · 80%", 80, nil),
        ("Виснажений · 92%", 92, nil),
        ("Паніка · 97%", 97, nil),
        ("Спить", 20, "sleep"),
        ("Свято", 20, "party"),
        ("Новорічна шапка", 20, "winter"),
        ("Махає", 20, "wave"),
        ("П'є каву", 20, "coffee"),
        ("Окуляри", 20, "shades"),
        ("Хелловін", 20, "halloween"),
        ("Сумує (тебе нема)", 20, "lonely"),
        ("Радіє (ти повернувся)", 20, "welcome"),
        ("Обідає", 20, "lunch"),
        ("Диско (п'ятниця)", 20, "disco"),
        ("Сонний понеділок", 20, "monday"),
        ("Мишка наведена", 20, "hover"),
        ("Лякається чайки", 20, "scared"),
        ("Сердиться на чайку", 20, "angry"),
        ("Падає", 20, "fall"),
        ("Летить на батуті", 20, "fly"),
        ("Схоплений мишкою", 20, "held"),
        ("Паморочиться", 20, "dizzy"),
        ("Клацає біля курсора", 20, "snip"),
        ("Валентинка", 20, "valentine"),
        ("День Незалежності", 20, "flag"),
        ("Танцює + еквалайзер", 20, "dance"),
        ("Кіберпсихоз (поза)", 97, "psycho"),
        ("Рок: соло на гітарі", 20, "riff"),
        ("Рок: хедбенг · 80%", 80, "headbang")]
    // Вікно з графіком
    var graphWin: NSWindow?
    var graphView: GraphView?
    @objc func showGraph() {
        if graphWin == nil {
            let v = GraphView(frame: NSRect(x: 0, y: 0, width: 820, height: 440))
            v.crabImage = { [unowned self] pct, _ in self.mascot(pct, frame: self.frame) }
            let w = NSWindow(contentRect: v.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Claude Limits · історія"
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.acceptsMouseMovedEvents = true
            w.minSize = NSSize(width: 520, height: 320)
            w.contentView = v
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak v] _ in v?.stop() }
            graphWin = w; graphView = v
        }
        graphView?.data = History.load(since: Date().addingTimeInterval(-8 * 86400))
        graphView?.start()
        graphWin?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    var shownPct: Double? { debugIndex == 0 ? top : App.debugStates[debugIndex].1 }
    @objc func pickDebug(_ s: NSMenuItem) {
        debugIndex = s.tag
        debugForce = App.debugStates[debugIndex].2
        render()
    }

    // Мишка: наведена на краба (червоніє) або поруч (дивиться в її бік).
    func updateMouse() {
        guard let r = item.button?.window?.frame else { return }
        let m = NSEvent.mouseLocation
        isHover = r.contains(m)
        let dx = m.x - r.midX
        lookDx = abs(dx) < 300 ? (dx < -12 ? -1 : dx > 12 ? 1 : 0) : 0
    }
    // Скільки секунд ніхто не чіпав мишку й клавіатуру. 10+ хв: краб сумує; повернувся: радіє.
    func checkIdle() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let was = isLonely
        isLonely = idle >= 600
        if was && !isLonely { welcomeUntil = frame + 30 }
    }
    func tick() {
        frame += 1
        lastFrameTime = Date()
        updateMouse()
        if frame % 7 == 0 { checkIdle() }
        if frame % 40 == 0 {                                               // ≈ раз на 6 с: якщо ліміт щойно «скинувся», показати це одразу
            let key = "\(usage?.session?.live.wasReset ?? false)\(usage?.weekly?.live.wasReset ?? false)"
            if key != liveKey { liveKey = key; render() }
        }                   // приблизно раз на секунду
        if frame >= nextCool { coolUntil = frame + 67; nextCool = frame + Int.random(in: 15 * App.perMinute...30 * App.perMinute) }
        if frame >= nextWalk { if canPlay() { pickScene() }; nextWalk = frame + Int.random(in: 25 * App.perMinute...45 * App.perMinute) }
        if frame >= nextGull { if canPlay() { startGull() }; nextGull = frame + Int.random(in: 40 * App.perMinute...90 * App.perMinute) }
        isDancing = debugForce == "dance"                                              // справжній звук: окремий крок (потрібен дозвіл)
        if frame >= nextPsycho {
            if cyber && (hotValue ?? 0) >= 95 && !homeHidden && !menuOpen && !isLonely { startPsycho() }
            nextPsycho = frame + Int.random(in: 800...2000)                            // раз на 2–5 хв
        }
        if frame >= nextSmash {                                                        // рок: від 95% розбиває гітару раз на 2–5 хв
            if rock && (hotValue ?? 0) >= 95 && !homeHidden && !menuOpen && !isLonely && psycho == nil { startSmash() }
            nextSmash = frame + Int.random(in: 800...2000)
        }
        updatePlay()
        ensureFastTimer()
        if isLonely && frame % 4 != 0 && walkStart < 0 && gullStart < 0 && tramp == nil && snip == nil && dragMode == .none && psycho == nil { return }   // поки тебе нема, малюємо вчетверо рідше
        setIcon(homeHidden ? blankIcon : mascot(shownPct, frame: frame))
        if glitchOn && (brokenFrame(frame) || frame < forceBrokenUntil) {                // цифри теж глючать
            if let g = glitchTitle() { item.button?.attributedTitle = g; titleGlitched = true }
        } else if titleGlitched { titleGlitched = false; if let t = lastTitle { item.button?.attributedTitle = t } }
    }

    func render() {
        guard let btn = item.button else { return }
        // Краб реагує на більший із двох лімітів, без поправок: настрій, колір цифр і глітч реагують на одне й те саме число.
        top = [usage?.session?.live.percent, usage?.weekly?.live.percent].compactMap { $0 }.max()
        lastIconBytes = Data(); lastIconBlank = false
        setIcon(homeHidden ? blankIcon : mascot(shownPct, frame: frame))
        btn.imagePosition = .imageLeft
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let t = NSMutableAttributedString()
        let bold = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .heavy)
        func add(_ s: String, _ c: NSColor = .labelColor, hot: Bool = false) {
            t.append(NSAttributedString(string: s, attributes: [.font: hot ? bold : font, .foregroundColor: c]))
        }
        if let u = usage {
            add("5г ", .secondaryLabelColor)
            if let s = u.session?.live { add("\(Int(s.percent.rounded()))%", color(s.percent), hot: s.percent >= 70) } else { add("—") }
            add("  Т ", .secondaryLabelColor)
            if let w = u.weekly?.live { add("\(Int(w.percent.rounded()))%", color(w.percent), hot: w.percent >= 70) } else { add("—") }
        } else { add(error == nil ? "…" : "⚠︎") }
        btn.attributedTitle = t
        lastTitle = t

        let m = NSMenu()
        func row(_ s: String) { let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i) }
        if let u = usage {
            if let s = u.session?.live { row(s.wasReset ? "Сесія 5 год: скинулась · чекаю свіжих даних" : "Сесія 5 год: \(Int(s.percent.rounded()))% · оновиться через \(left(s.resets))") }
            if let w = u.weekly?.live { row(w.wasReset ? "Тиждень: скинувся · чекаю свіжих даних" : "Тиждень: \(Int(w.percent.rounded()))% · оновиться через \(left(w.resets))") }
        }
        if let e = error { row("⚠︎ \(e)") }
        if usage == nil && error == nil {
            if nextAllowed > Date() {
                let f = DateFormatter(); f.dateFormat = "HH:mm"
                row("Сервер тимчасово обмежив запити · наступна спроба о \(f.string(from: nextAllowed))")
            } else { row("Завантажую…") }
        }
        if let up = updated {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            row(stale ? "Дані з \(f.string(from: up)) · сервер просить зачекати" : "Оновлено \(f.string(from: up))")
        }
        m.addItem(.separator())
        let gr = NSMenuItem(title: "Графік використання…", action: #selector(showGraph), keyEquivalent: "g"); gr.target = self; m.addItem(gr)
        let cy = NSMenuItem(title: "Кіберпанк-режим", action: #selector(toggleCyber), keyEquivalent: ""); cy.target = self; cy.state = cyber ? .on : .off; m.addItem(cy)
        let rk = NSMenuItem(title: "Рок-зірка 🎸", action: #selector(toggleRock), keyEquivalent: ""); rk.target = self; rk.state = rock ? .on : .off; m.addItem(rk)
        let dbg = NSMenuItem(title: "Дебаг: стани краба", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (i, st) in App.debugStates.enumerated() {
            let it = NSMenuItem(title: st.0, action: #selector(pickDebug(_:)), keyEquivalent: "")
            it.target = self; it.tag = i; it.state = i == debugIndex ? .on : .off
            sub.addItem(it)
        }
        sub.addItem(.separator())
        let dw = NSMenuItem(title: "Піти погуляти зараз", action: #selector(debugWalk), keyEquivalent: ""); dw.target = self; sub.addItem(dw)
        let dt = NSMenuItem(title: rock ? "Стейдж-дайв на Dock" : "Батут на Dock", action: #selector(debugTramp), keyEquivalent: ""); dt.target = self; sub.addItem(dt)
        let ds = NSMenuItem(title: "Розбити гітару зараз", action: #selector(debugSmash), keyEquivalent: ""); ds.target = self; sub.addItem(ds)
        let dp = NSMenuItem(title: "Кіберпсихоз зараз", action: #selector(debugPsycho), keyEquivalent: ""); dp.target = self; sub.addItem(dp)
        let dc = NSMenuItem(title: "Ловити курсор", action: #selector(debugSnip), keyEquivalent: ""); dc.target = self; sub.addItem(dc)
        let dh = NSMenuItem(title: "Сховатися в камері", action: #selector(debugHide), keyEquivalent: ""); dh.target = self; sub.addItem(dh)
        let dg = NSMenuItem(title: "Чайка прилетіла", action: #selector(debugGull), keyEquivalent: ""); dg.target = self; sub.addItem(dg)
        dbg.submenu = sub; m.addItem(dbg)
        let ac = NSMenuItem(title: "Дозвіл для Dock…", action: #selector(askAccess), keyEquivalent: ""); ac.target = self; m.addItem(ac)
        let r = NSMenuItem(title: "Оновити зараз", action: #selector(manual), keyEquivalent: "r"); r.target = self; m.addItem(r)
        m.addItem(NSMenuItem(title: "Вийти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        m.delegate = self
        currentMenu = m
    }
    @objc func manual() { refresh() }
    func refreshTimer() { refresh() }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    let d = App()
    let states = Array(App.debugStates.dropFirst())
    let cols = 6, scale: CGFloat = 8, w: CGFloat = 15 * 2 * scale, h: CGFloat = 10 * 2 * scale, pad: CGFloat = 16
    let rowsN = (states.count + cols - 1) / cols + 3   // + рядки з чайкою, кажаном і кіберефектами
    let sheet = NSImage(size: NSSize(width: (w + pad) * CGFloat(cols) + pad, height: (h + pad) * CGFloat(rowsN) + pad))
    sheet.lockFocus()
    NSColor(white: 0.18, alpha: 1).setFill(); NSRect(origin: .zero, size: sheet.size).fill()
    for (n, st) in states.enumerated() {
        d.debugForce = st.2
        let img = d.mascot(st.1, frame: 5)
        let c = n % cols, r = n / cols
        img.draw(in: NSRect(x: pad + CGFloat(c) * (w + pad), y: sheet.size.height - (h + pad) * CGFloat(r + 1), width: w, height: h))
    }
    d.debugForce = "glitch"                                           // глітч на 97% (4 «зламані» кадри) і голограма
    let broken = (0..<60).filter { d.brokenFrame($0) }.prefix(3)
    for (n, fr) in broken.enumerated() {
        let g = d.mascot(97, frame: fr)
        g.draw(in: NSRect(x: pad + CGFloat(n) * (w + pad), y: pad + 2 * (h + pad), width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    d.debugForce = nil
    if let hg = d.hologram(d.mascotBase(40, frame: 1), f: 1) {
        hg.draw(in: NSRect(x: pad + 3 * (w + pad), y: pad + 2 * (h + pad), width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    let eq = d.eqImage(level: 0.9, f: 3)
    eq.draw(in: NSRect(x: pad + 4 * (w + pad), y: pad + 2 * (h + pad), width: eq.size.width * scale, height: eq.size.height * scale), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    for n in 0..<4 {                                                  // кажан: 4 фази змаху (Хелловін)
        d.debugForce = "halloween"
        let g = d.gullImage(n * 2)
        g.draw(in: NSRect(x: pad + CGFloat(n) * (w + pad), y: pad + h + pad, width: g.size.width * scale, height: g.size.height * scale), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    d.debugForce = nil
    for n in 0..<4 {                                                  // чайка: 4 фази змаху
        let g = d.gullImage(n * 2)
        g.draw(in: NSRect(x: pad + CGFloat(n) * (w + pad), y: pad, width: g.size.width * scale, height: g.size.height * scale), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    for (n, sq) in [false, true].enumerated() {                       // батут: звичайний і прогнутий
        let t = d.trampolineImage(squash: sq)
        t.draw(in: NSRect(x: pad + CGFloat(4 + n) * (w + pad), y: pad + 40, width: t.size.width * scale, height: t.size.height * scale), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    sheet.unlockFocus()
    if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    }
    exit(0)
}
// ClaudeLimits --readme-images <папка>: картинки й GIF для README (таблиця станів із підписами, менюбар, анімації, сцена з батутом).
if let i = CommandLine.arguments.firstIndex(of: "--readme-images"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1]); try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let d = App()
    let bg = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)
    func canvas(_ w: Int, _ h: Int, _ draw: () -> Void) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .none
        bg.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        draw(); NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    func png(_ img: CGImage, _ name: String) { try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name)) }
    func gif(_ frames: [CGImage], _ delay: Double, _ name: String) {
        guard let dst = CGImageDestinationCreateWithURL(dir.appendingPathComponent(name) as CFURL, "com.compuserve.gif" as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(dst, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for f in frames { CGImageDestinationAddImage(dst, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary) }
        CGImageDestinationFinalize(dst)
    }
    func label(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 13, color: NSColor = NSColor(white: 0.85, alpha: 1)) {
        let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
        a.draw(at: NSPoint(x: x - a.size().width / 2, y: y))
    }
    // 1) таблиця станів із підписами (класичний вигляд; рок-зірку показує окрема GIF-ка)
    d.rock = false
    let states = Array(App.debugStates.dropFirst().filter { !$0.0.hasPrefix("Рок:") }), cols = 6, cw = 170, ch = 150, sc: CGFloat = 4
    let rows = (states.count + cols - 1) / cols
    png(canvas(cols * cw, rows * ch) {
        for (n, st) in states.enumerated() {
            d.debugForce = st.2
            let img = d.mascot(st.1, frame: 21)
            let c = n % cols, r = rows - 1 - n / cols
            let x = CGFloat(c * cw) + (CGFloat(cw) - 30 * sc) / 2, y = CGFloat(r * ch) + 34
            img.draw(in: NSRect(x: x, y: y, width: 30 * sc, height: 20 * sc), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            label(st.0, CGFloat(c * cw + cw / 2), CGFloat(r * ch) + 10)
        }
        d.debugForce = nil
    }, "crab-states.png")
    d.rock = true
    // 2) менюбар: краб + цифри на темній смузі (2x)
    png(canvas(520, 66) {
        NSColor(white: 0.17, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 520, height: 66).fill()
        d.mascot(42, frame: 2).draw(in: NSRect(x: 150, y: 13, width: 60, height: 40), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let t = NSMutableAttributedString()
        for (s, c) in [("5г ", NSColor(white: 0.6, alpha: 1)), ("42%", NSColor.white), ("   Т ", NSColor(white: 0.6, alpha: 1)), ("18%", NSColor.white)] {
            t.append(NSAttributedString(string: s, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium), .foregroundColor: c]))
        }
        t.draw(at: NSPoint(x: 222, y: 17))
        for (k, x) in [(0, 30.0), (1, 70.0), (2, 420.0), (3, 462.0)] { NSColor(white: 0.45 + 0.05 * Double(k), alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 22, width: 22, height: 22), xRadius: 5, yRadius: 5).fill() }
    }, "menubar.png")
    // 3) анімації краба: спокій, глітч 97%, танець
    func crabGIF(_ pct: Double, _ force: String?, _ n: Int, _ name: String) {
        d.debugForce = force
        let frames = (0..<n).map { f in canvas(240, 170) { d.mascot(pct, frame: f).draw(in: NSRect(x: 30, y: 25, width: 180, height: 120), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) } }
        gif(frames, 0.15, name); d.debugForce = nil
    }
    crabGIF(30, nil, 48, "crab-idle.gif")
    crabGIF(97, "glitch", 40, "crab-glitch.gif")
    crabGIF(20, "dance", 24, "crab-dance.gif")
    // рок-зірка: соло → хедбенг → розбиває гітару (з уламками) → піротехніка
    var rockFrames: [CGImage] = []
    func rockFrame(_ pct: Double, _ f: Int, debris: CGFloat? = nil) -> CGImage {
        canvas(240, 190) {
            d.mascot(pct, frame: f).draw(in: NSRect(x: 30, y: 30, width: 180, height: 120), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            if let tau = debris {
                for i in 0..<8 {
                    let vx = CGFloat(App.lcg(13 &+ i) % 13 - 6) * 0.9 * 4, vy = CGFloat(App.lcg(17 &+ i &* 7) % 8 + 3) * 4
                    [App.c(220, 30, 45), App.c(120, 78, 40), App.c(205, 210, 220)][i % 3].setFill()
                    NSRect(x: 175 + vx * tau, y: 70 + vy * tau - 2.4 * tau * tau, width: 9, height: 9).fill()
                }
            }
        }
    }
    d.debugForce = "riff"; for f in 0..<16 { rockFrames.append(rockFrame(20, f)) }
    d.debugForce = "headbang"; for f in 0..<12 { rockFrames.append(rockFrame(80, f)) }
    d.debugForce = nil; d.smash = App.Smash(start: 0)
    for f in 0..<34 { rockFrames.append(rockFrame(96, f, debris: f >= 6 && f < 30 ? CGFloat(f - 6) : nil)) }
    d.smash = nil; d.debugForce = "party"; for f in 0..<16 { rockFrames.append(rockFrame(20, f)) }
    d.debugForce = nil
    gif(rockFrames, 0.15, "rockstar.gif")
    // 4) сцена з батутом: менюбар зверху, Dock унизу, краб падає, відскакує, іде до іконки, сидить і летить назад (з неоновим слідом)
    let W: CGFloat = 270, H: CGFloat = 240, S: CGFloat = 2
    var t = App.Tramp(); t.hx = 215; t.hy = H - 26; t.tx = 70; t.dockTop = 36; t.ix = 200; t.iconTop = 36; t.walk = Int(abs(t.ix - t.tx) / 4)
    let sitStart = 12.0 + 28 + Double(t.walk) + 6, after = sitStart + 240
    var times: [Double] = []
    var tt = 0.0; while tt < sitStart + 12 { times.append(tt); tt += 0.5 }
    tt = after; while tt < after + 5 + Double(t.walk) + 14 + 20 { times.append(tt); tt += 0.5 }
    var trail: [NSPoint] = []
    var frames: [CGImage] = []
    for (k, tm) in times.enumerated() {
        guard let fr = d.trampFrame(t, tm) else { break }
        d.playPose = fr.pose; d.isWalking = fr.walking; d.lookDx = fr.look
        let crab = d.mascot(20, frame: k / 2)
        let pos = NSPoint(x: fr.x - 15, y: fr.y - 2)
        if let l = trail.last { if hypot(pos.x - l.x, pos.y - l.y) >= 6 { trail.append(pos) } } else { trail.append(pos) }
        if trail.count > 6 { trail.removeFirst() }
        frames.append(canvas(Int(W * S), Int(H * S)) {
            NSGraphicsContext.current?.cgContext.scaleBy(x: S, y: S)
            NSColor(white: 0.17, alpha: 1).setFill(); NSRect(x: 0, y: H - 30, width: W, height: 30).fill()                     // менюбар
            NSColor(white: 0.26, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 18, y: 4, width: W - 36, height: 32), xRadius: 10, yRadius: 10).fill()   // Dock
            let icons: [NSColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple, .systemTeal, .systemYellow]
            for (n, c) in icons.enumerated() { c.setFill(); NSBezierPath(roundedRect: NSRect(x: 28 + CGFloat(n) * 32, y: 8, width: 24, height: 24), xRadius: 6, yRadius: 6).fill() }
            let sil = d.silhouette(crab, App.c(0, 230, 255))
            for (n, p) in trail.dropLast().enumerated() { sil.draw(in: NSRect(x: p.x, y: p.y, width: 30, height: 20), from: .zero, operation: .sourceOver, fraction: 0.06 + 0.25 * CGFloat(n) / 5) }
            d.trampolineImage(squash: fr.squash).draw(in: NSRect(x: t.tx - 19.5, y: t.dockTop, width: 39, height: 12), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            crab.draw(in: NSRect(x: pos.x, y: pos.y, width: 30, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        })
    }
    gif(frames, 0.05, "trampoline.gif")
    print("готово: \(dir.path)"); exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--preview-graph"), i + 1 < CommandLine.arguments.count {
    let d = App()
    let v = GraphView(frame: NSRect(x: 0, y: 0, width: 820, height: 440))
    v.week = CommandLine.arguments.contains("week")
    v.crabImage = { d.mascot($0, frame: $1) }
    var seed: UInt64 = 7
    func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
    var sess = 0.0, w = 5.0
    var t = Date().addingTimeInterval(-7 * 86400)
    while t < Date() {
        let h = Calendar.current.component(.hour, from: t), mi = Calendar.current.component(.minute, from: t)
        if h % 5 == 0 && mi < 5 { sess = 0 }
        if h >= 9 && h < 20 { let add = rnd() * 1.6; sess = min(100, sess + add); w = min(100, w + add / 9) }
        if !(h >= 1 && h < 8 && rnd() < 0.25) { v.data.append(Sample(t: t, s: sess, w: w)) }
        t = t.addingTimeInterval(300)
    }
    v.hoverX = 820 * 2 / 3
    v.display()
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
