# InGe+ Android - Reglas obligatorias

## Mision

Terminar InGe+ Android v1.0.0 usando Qt 6.9.3, C++, QML, CMake,
Android arm64-v8a, Supabase, almacenamiento local, QXlsx e InGeCoreFlow.

## Fuente de verdad

Trabaja exclusivamente sobre los archivos fuente de este repositorio.
No trabajes sobre build, qmlcache, APK extraidas, ZIP o parches anteriores.

## Reglas

1. Corrige el codigo madre; no uses BAT/PowerShell/ZIP como solucion tecnica.
2. No ocultes errores con el fallback.
3. Una sola implementacion activa por pagina y un solo Main.qml real.
4. Un solo motor global InGeCoreFlow.
5. No crear otro sistema de animaciones.
6. No romper Login, Supabase, AuthSession, multicuenta, Perfil o Home.
7. Nunca usar service_role en Android.
8. El correo debe conservarse exactamente como fue escrito.
9. La capitalizacion automatica solo puede aplicarse visualmente a nombres.
10. Mantener compatibilidad Qt 6.9.3 y Android arm64-v8a.
11. Elegir una sola estrategia de registro QML por tipo.
12. Alinear CMake, QRC, qmldir, imports, URI y archivos fisicos.
13. No borrar datos locales durante migraciones.
14. Usar Git y un commit por fase.
15. No declarar exito sin build, instalacion, logcat y pruebas reales.
16. Ejecutar tareas secuencialmente y esperar lo necesario.
17. No imprimir secretos ni contrasenas en logs.
18. El rediseño final de iconos ocurre despues de Configuracion y temas.

## Ciclo de validacion

- Run CMake cuando corresponda.
- Build Android arm64-v8a.
- Instalar APK.
- Limpiar logcat.
- Iniciar app por ADB.
- Revisar errores QML/crash/ANR.
- Ejecutar regresion.
- Documentar y crear commit.

## Definicion de terminado

Una tarea solo termina con archivos modificados, causa raiz, comandos,
build real, instalacion, logcat, pruebas, riesgos y commit.
