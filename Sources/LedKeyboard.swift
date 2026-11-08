// Led Keyboard — pulsations et réaction à la frappe sur le rétroéclairage du clavier MacBook.
// Utilise le framework privé CoreBrightness (KeyboardBrightnessClient), chargé dynamiquement.

import Cocoa
import SwiftUI
import ApplicationServices

// MARK: - Accès au rétroéclairage (CoreBrightness, privé)

final class KeyboardBacklight {
    private let client: NSObject
    let keyboardID: UInt64

    private typealias GetFn      = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn      = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias SetFadeFn  = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
    private typealias BoolKbFn   = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
    private typealias VoidBoolFn = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Void
    private typealias IsFn       = @convention(c) (AnyObject, Selector, UInt64) -> Bool

    init?() {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              bundle.load(),
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        client = cls.init()

        var id: UInt64 = 1 // valeur habituelle sur Apple Silicon
        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        if client.responds(to: idsSel),
           let ids = client.perform(idsSel)?.takeRetainedValue() as? [NSNumber],
           let first = ids.first {
            id = first.uint64Value
        }
        keyboardID = id
    }

    private func fn<T>(_ name: String, _ type: T.Type) -> (Selector, T)? {
        let sel = NSSelectorFromString(name)
        guard client.responds(to: sel), let imp = client.method(for: sel) else { return nil }
        return (sel, unsafeBitCast(imp, to: T.self))
    }

    var brightness: Float {
        guard let r = fn("brightnessForKeyboard:", GetFn.self) else { return 0.5 }
        return r.1(client, r.0, keyboardID)
    }

    /// Règle la luminosité (0…1) instantanément, sans l'enregistrer comme réglage utilisateur.
    func set(_ value: Float) {
        let v = max(0, min(1, value))
        if let r = fn("setBrightness:fadeSpeed:commit:forKeyboard:", SetFadeFn.self) {
            _ = r.1(client, r.0, v, 0, false, keyboardID)
        } else if let r = fn("setBrightness:forKeyboard:", SetFn.self) {
            _ = r.1(client, r.0, v, keyboardID)
        }
    }

    /// Valeur finale « officielle » (enregistrée), utilisée à la fermeture.
    func commit(_ value: Float) {
        if let r = fn("setBrightness:fadeSpeed:commit:forKeyboard:", SetFadeFn.self) {
            _ = r.1(client, r.0, value, 250, true, keyboardID)
        } else {
            set(value)
        }
    }

    var autoBrightness: Bool {
        guard let r = fn("isAutoBrightnessEnabledForKeyboard:", IsFn.self) else { return false }
        return r.1(client, r.0, keyboardID)
    }

    func setAutoBrightness(_ on: Bool) {
        guard let r = fn("enableAutoBrightness:forKeyboard:", BoolKbFn.self) else { return }
        _ = r.1(client, r.0, on, keyboardID)
    }

    /// Empêche macOS d'éteindre le clavier après inactivité pendant que l'app tourne.
    func suspendIdleDimming(_ on: Bool) {
        guard let r = fn("suspendIdleDimming:forKeyboard:", VoidBoolFn.self) else { return }
        r.1(client, r.0, on, keyboardID)
    }
}

// MARK: - Moteur d'animation

enum Mode: String, CaseIterable, Identifiable {
    case reactive = "Réactif"
    case pulse    = "Respiration"
    case both     = "Les deux"
    case off      = "Arrêt"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .reactive: return "keyboard"
        case .pulse:    return "wind"
        case .both:     return "sparkles"
        case .off:      return "power"
        }
    }
}

final class Engine: ObservableObject {
    static let shared = Engine()
    private let d = UserDefaults.standard

    @Published var mode: Mode { didSet { d.set(mode.rawValue, forKey: "mode"); modeChanged() } }
    @Published var maxLevel: Double { didSet { d.set(maxLevel, forKey: "maxLevel") } }
    @Published var pulsePeriod: Double { didSet { d.set(pulsePeriod, forKey: "pulsePeriod") } }
    @Published var fadeTime: Double { didSet { d.set(fadeTime, forKey: "fadeTime") } }
    @Published var accessibilityOK = false
    @Published var keyCount = 0

    let backlight = KeyboardBacklight()
    private var savedBrightness: Float = 0.5
    private var savedAuto = false
    private var timer: Timer?
    private var permTimer: Timer?
    private var monitors: [Any] = []
    private var flash: Double = 0
    private var phase: Double = 0
    private var lastTick = CACurrentMediaTime()
    private var lastSent: Double = -1

    private init() {
        mode        = Mode(rawValue: d.string(forKey: "mode") ?? "") ?? .reactive
        maxLevel    = d.object(forKey: "maxLevel") as? Double ?? 1.0
        pulsePeriod = d.object(forKey: "pulsePeriod") as? Double ?? 3.0
        fadeTime    = d.object(forKey: "fadeTime") as? Double ?? 0.6
    }

    func start() {
        guard let bl = backlight else { return }
        savedBrightness = bl.brightness
        savedAuto = bl.autoBrightness
        setupKeyMonitoring()
        modeChanged()
    }

    private func modeChanged() {
        guard let bl = backlight else { return }
        if mode == .off {
            timer?.invalidate(); timer = nil
            bl.suspendIdleDimming(false)
            bl.setAutoBrightness(savedAuto)
            bl.commit(savedBrightness)
            lastSent = -1
            return
        }
        bl.setAutoBrightness(false)
        bl.suspendIdleDimming(true)
        if timer == nil {
            lastTick = CACurrentMediaTime()
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTick)
        lastTick = now

        // Décroissance du flash : ~1 % restant après `fadeTime` secondes.
        flash *= pow(0.01, dt / max(0.05, fadeTime))
        if flash < 0.002 { flash = 0 }

        phase = (phase + dt / max(0.3, pulsePeriod)).truncatingRemainder(dividingBy: 1)
        let breath = pow((1 - cos(2 * .pi * phase)) / 2, 1.6)

        let raw: Double
        switch mode {
        case .reactive: raw = flash
        case .pulse:    raw = breath
        case .both:     raw = max(breath * 0.35, flash)
        case .off:      return
        }
        let level = min(1, raw) * maxLevel
        if abs(level - lastSent) > 0.003 || (level == 0 && lastSent != 0) {
            backlight?.set(Float(level))
            lastSent = level
        }
    }

    func keyPressed() {
        flash = 1
        keyCount &+= 1
    }

    // MARK: Détection de la frappe (nécessite Accessibilité)

    private func setupKeyMonitoring() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityOK = AXIsProcessTrustedWithOptions(opts)
        // Moniteur local : fonctionne même sans permission quand le panneau de l'app est actif.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            self?.keyPressed(); return e
        }) { monitors.append(m) }

        if accessibilityOK {
            installGlobalMonitor()
        } else {
            // Attend que l'utilisateur accorde la permission, puis installe le moniteur global.
            permTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                guard let self, AXIsProcessTrusted() else { return }
                t.invalidate()
                self.accessibilityOK = true
                self.installGlobalMonitor()
            }
        }
    }

    private func installGlobalMonitor() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            self?.keyPressed()
        }) { monitors.append(m) }
    }

    func restore() {
        timer?.invalidate()
        guard let bl = backlight else { return }
        bl.suspendIdleDimming(false)
        bl.setAutoBrightness(savedAuto)
        bl.commit(savedBrightness)
    }
}

// MARK: - Interface (barre des menus)

struct PanelView: View {
    @ObservedObject var engine = Engine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "light.max")
                Text("Led Keyboard").font(.headline)
                Spacer()
                Text("\(engine.keyCount) frappes").font(.caption).foregroundStyle(.secondary)
            }

            if engine.backlight == nil {
                Label("Rétroéclairage introuvable (CoreBrightness indisponible).", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout)
            }

            HStack(spacing: 6) {
                ForEach(Mode.allCases) { m in
                    Button { engine.mode = m } label: {
                        VStack(spacing: 4) {
                            Image(systemName: m.icon).font(.system(size: 15))
                            Text(m.rawValue).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(engine.mode == m ? Color.accentColor : Color.primary.opacity(0.06)))
                        .foregroundStyle(engine.mode == m ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            slider("Intensité max", value: $engine.maxLevel, range: 0.1...1, format: "%.0f %%", scale: 100)
            if engine.mode == .pulse || engine.mode == .both {
                slider("Durée d'une respiration", value: $engine.pulsePeriod, range: 0.5...8, format: "%.1f s")
            }
            if engine.mode == .reactive || engine.mode == .both {
                slider("Durée d'extinction", value: $engine.fadeTime, range: 0.1...3, format: "%.1f s")
            }

            if !engine.accessibilityOK && engine.mode != .pulse {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pour réagir à la frappe dans toutes les apps, autorise Led Keyboard dans Réglages › Confidentialité › Accessibilité.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir les réglages Accessibilité") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, scale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { Engine.shared.start() }
    func applicationWillTerminate(_ n: Notification) { Engine.shared.restore() }
}

@main
struct LedKeyboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Led Keyboard", systemImage: "keyboard") {
            PanelView()
        }
        .menuBarExtraStyle(.window)
    }
}
