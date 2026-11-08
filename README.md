# Led Keyboard

App de barre des menus qui anime le rétroéclairage du clavier du MacBook.

## Modes
- **Réactif** : clavier éteint, chaque touche l'allume à fond puis il s'éteint en douceur.
- **Respiration** : pulsation lente continue.
- **Les deux** : respiration faible en fond + flash à chaque frappe.
- **Arrêt** : rend la luminosité d'origine.

Réglages : intensité max, durée d'une respiration, durée d'extinction (sauvegardés).

## Installer
Prérequis : un MacBook Apple Silicon avec clavier rétroéclairé, macOS 13+, Xcode ou les Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/lucasmartin042009-sudo/led-keyboard.git
cd led-keyboard
bash build.sh
open "build/Led Keyboard.app"
```

L'icône clavier apparaît dans la barre des menus.
4. Autorise l'app dans **Réglages › Confidentialité et sécurité › Accessibilité** pour qu'elle voie la frappe dans toutes les apps.

## Diagnostic
Si la lumière ne réagit pas : `swift Tools/diag.swift` fait clignoter le clavier 3 fois et affiche ce que le système accepte.

## À savoir
- Utilise le framework **privé** CoreBrightness : pas publiable sur l'App Store, et une mise à jour de macOS peut le casser.
- Signature ad hoc : après chaque recompilation, macOS peut oublier la permission Accessibilité → retire l'app de la liste et rajoute-la.
- L'app ne lit que le fait qu'une touche est pressée, jamais laquelle.
- À la fermeture (Quitter), la luminosité et le réglage automatique d'origine sont restaurés.

## Licence
MIT
