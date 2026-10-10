import QtQuick
import QtQuick.Window

// InGe+ sin interfaz (Visual Zero, 2026-10-10). Única estructura mínima que
// exige Qt para arrancar en Android: una ventana sin controles, textos, iconos,
// menús ni animaciones. Los servicios funcionales (Supabase, sesión,
// sincronización, exportaciones, Rendiciones, documentos, GPS) se crean en
// main_mobile.cpp y siguen activos. La lógica de dominio que vivía en las
// pantallas está en lib/*.js (CalicataFormLogic, CalicataWorkspaceLogic,
// AccountText, PhotoEditSchema, CalicataRules...).
Window {
    visible: true

    // Restauración de la sesión recordada (servicio sin interfaz). Sin sesión
    // restaurable no hay forma de iniciar sesión hasta la nueva interfaz.
    Component.onCompleted: {
        if (typeof auth !== "undefined" && auth && auth.hasRestorableSession()) {
            console.info("INGE_HEADLESS_SESSION_RESTORE begin")
            auth.tryAutoLogin()
        } else {
            console.info("INGE_HEADLESS_SESSION_RESTORE none")
        }
    }
}
