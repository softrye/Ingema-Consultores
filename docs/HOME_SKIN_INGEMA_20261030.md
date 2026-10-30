# Home y skin Ingema

- Retirada la tarjeta Agregar del Home; el acceso del Dock conserva openAdd(),
  el panel existente y su comportamiento durante edición de tarjetas.
- Añadida Ingema / Consultores en Ajustes → Apariencia → Skins. La selección
  usa la preferencia persistente existente appearancePrefs.skin, clave ingema.
- Selector Flow de dos columnas para que las tres skins no excedan el ancho.
- El fondo compartido reconoce ingema y reutiliza AuroraField. Home mantiene
  textos blancos sobre azul marino; Ajustes, Calicatas y Rendiciones conservan
  el modo claro/oscuro. Movimiento reducido y pausa en segundo plano siguen activos.
- Logos locales existentes, con aliases ya presentes en resources_mobile_brand.qrc;
  no se agregan assets, imports, URI ni otro sistema de animación.

Referencia de sólo lectura: Web del ZIP proporcionado. InternalShell.tsx usa
#06111F y #071A33; renditionExportTheme.ts documenta #0654A2 y #486426.
El ZIP no contiene un selector de skins Ingema; se implementa su identidad
corporativa, sin afirmar que sea una reproducción de un tema Web no disponible.

Fuentes: HomeScreen.qml, settings/SettingsApp.qml y
renditions/RendicionesSyncBackdrop.qml, bajo qml/Mobile.

Comprobaciones sin build:
- Node: tests/home_add_tools_dock.cjs + dock_first_tap_static.cjs, 11/11.
- qmltestrunner Qt 6.9.3 offscreen: tst_IngemaSkin.qml, 7/7;
  tst_render_stability.qml, 15/15.
- Las pruebas de la skin y de la tarjeta duplicada fallaron antes de los cambios.

No se ejecutaron CMake, build, instalación ni reinicio. Queda pendiente comprobar
el aspecto y la persistencia en el A12 después de la compilación del usuario.
SettingsApp.qml y RendicionesSyncBackdrop.qml ya eran fuentes nuevas sin commit;
se conservan con sus cambios anteriores. Compilar el árbol de trabajo completo.
