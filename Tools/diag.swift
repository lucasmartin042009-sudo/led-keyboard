// Diagnostic du rétroéclairage — lance avec : swift diag.swift
import Foundation

typealias GetFn  = @convention(c) (AnyObject, Selector, UInt64) -> Float
typealias IsFn   = @convention(c) (AnyObject, Selector, UInt64) -> Bool
typealias SetFn  = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
typealias AutoFn = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool

guard let b = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework") else {
    print("❌ CoreBrightness introuvable"); exit(1)
}
print("Chargement framework :", b.load() ? "✅" : "❌")
guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
    print("❌ Classe KeyboardBrightnessClient introuvable"); exit(1)
}
let c = cls.init()

let sels = ["copyKeyboardBacklightIDs", "brightnessForKeyboard:", "setBrightness:forKeyboard:",
            "setBrightness:fadeSpeed:commit:forKeyboard:", "enableAutoBrightness:forKeyboard:",
            "isAutoBrightnessEnabledForKeyboard:", "suspendIdleDimming:forKeyboard:",
            "isBacklightSuppressedOnKeyboard:", "isBacklightSaturatedOnKeyboard:"]
for s in sels { print(c.responds(to: NSSelectorFromString(s)) ? "✅" : "❌", s) }

var id: UInt64 = 1
if let ids = c.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber] {
    print("IDs clavier :", ids)
    if let f = ids.first { id = f.uint64Value }
} else { print("⚠️ Aucun ID renvoyé, j'essaie 1") }

func call<T>(_ s: String, _ t: T.Type) -> (Selector, T)? {
    let sel = NSSelectorFromString(s)
    guard c.responds(to: sel), let imp = c.method(for: sel) else { return nil }
    return (sel, unsafeBitCast(imp, to: T.self))
}

let get = call("brightnessForKeyboard:", GetFn.self)
let set = call("setBrightness:forKeyboard:", SetFn.self)
let original = get.map { $0.1(c, $0.0, id) } ?? -1
print("Luminosité actuelle :", original)
if let r = call("isAutoBrightnessEnabledForKeyboard:", IsFn.self) { print("Auto :", r.1(c, r.0, id)) }
if let r = call("isBacklightSuppressedOnKeyboard:", IsFn.self) { print("Supprimé (pièce trop claire ?) :", r.1(c, r.0, id)) }

if let r = call("enableAutoBrightness:forKeyboard:", AutoFn.self) { _ = r.1(c, r.0, false, id) }

guard let set else { print("❌ Impossible de régler la luminosité"); exit(1) }
print("\n👀 Regarde ton clavier : il doit clignoter 3 fois…")
for _ in 0..<3 {
    print("  set 1 →", set.1(c, set.0, 1, id)); Thread.sleep(forTimeInterval: 0.8)
    print("  set 0 →", set.1(c, set.0, 0, id)); Thread.sleep(forTimeInterval: 0.8)
}
if let g = get { print("Luminosité lue après :", g.1(c, g.0, id)) }
_ = set.1(c, set.0, original < 0 ? 0.5 : original, id)
print("Terminé, luminosité restaurée.")
