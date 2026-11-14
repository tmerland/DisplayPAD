// main.swift — point d'entrée explicite (fonctionne avec ou sans bundle .app)
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)   // logs immédiats même redirigés vers un fichier

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // app de barre des menus, pas d'icône Dock
    app.run()
}
