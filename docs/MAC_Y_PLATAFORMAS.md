# Desarrollo y revisión desde el Mac

El Mac es el equipo de desarrollo. Por petición del usuario del 6 de octubre de 2026 no se entrega una aplicación macOS. Los clientes previstos siguen siendo Windows, Android e iOS; la demostración se revisa en navegador.

## Herramientas comprobadas

Mac Apple Silicon, macOS 27.0.1; Flutter 3.47.6 y Dart 3.13.5 preparados en `../../work/flutter` respecto al proyecto. El SDK temporal no se incluye en el ZIP del código. Xcode 27 está instalado desde Apple y reconoce la cuenta del usuario con un Personal Team. No se ha contratado una membresía Apple. Android Studio está instalado y las herramientas oficiales descargadas/verificadas. El gestor encuentra siete licencias del SDK pendientes; su aceptación personal y la instalación del SDK/emulador siguen abiertas.

La compilación web, el analizador y las pruebas locales funcionan desde este Mac. La demo utiliza datos ficticios y servidor simulado. No proporciona acceso al taller alojado.

## Revisar la demo

En la carpeta de la demo ejecuta **Abrir TallerFlow.command**. Utiliza Python 3 y abre `http://127.0.0.1:8777/`. Si ya está abierta, recarga la página después de actualizar sus archivos. Configuración permite cambiar de perfil y simular dos móviles y oficina.

## Compilar las aplicaciones

En el repositorio privado `benjapija/tallerflow`, Actions → **TallerFlow · validar y compilar** realiza las comprobaciones y genera Windows, Android e iOS simulador. El trabajo iOS utiliza un Mac alojado; el ejecutable de oficina se genera en Windows. No necesitas instalar Visual Studio en tu Mac.

La primera ejecución ya produjo Windows con instalador Inno Setup, APK debug Android e iOS simulador. Son compilaciones del commit c6f9c09, anteriores al código actual de cuentas, historial y precios. Los archivos originales se conservan identificados como `compilacion-1`; no son una versión completa del piloto.

Un segundo workflow, **TallerFlow · validar Windows nativo**, ha ejecutado dos procesos reales de la aplicación en Windows Server 2025 alojado. Comprueba almacenamiento cifrado, Credential Manager, conservación de registros sin conexión, reinicio y sincronización sin duplicados. El servidor es ficticio. Instalador, actualización/desinstalación y cuentas Supabase reales requieren comprobaciones adicionales. Evidencias: `evidence/windows-native-validation.json` y su ZIP de registros.

El cliente conectado utiliza `config/pilot.public.json`: URL, clave publicable y taller ficticio. Nunca añadas contraseña de base de datos, clave de servicio ni clave OpenAI. El primer acceso de cada cuenta necesita conexión.

## iOS y Android

Desde el Mac, con un simulador o dispositivo autorizado y su SDK disponible:

```sh
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d ID_DISPOSITIVO --dart-define-from-file=config/pilot.public.json
```

El simulador iOS necesita los componentes de Xcode y acceso a sus carpetas normales de caché. Las herramientas de esta conversación no han recibido ese permiso; no afecta a la compilación alojada. Android necesita su SDK. El usuario ha indicado que no dispone de más teléfonos: no se da por comprobado un equipo físico ni se compra ninguno.

Las versiones se fijan en `pubspec.lock`. Android mínimo 24 y copias automáticas desactivadas para evitar restaurar un almacén sin su clave; iOS mínimo efectivo 15 por el selector de archivos. Las declaraciones de plataforma de los paquetes no sustituyen pruebas de funcionamiento.

Referencias: [Flutter iOS](https://docs.flutter.dev/platform-integration/ios/setup), [Flutter Android](https://docs.flutter.dev/platform-integration/android/setup), [Flutter Windows](https://docs.flutter.dev/platform-integration/windows/building), [instalación Flutter](https://docs.flutter.dev/install/manual), [almacenamiento seguro](https://pub.dev/packages/flutter_secure_storage).

Las próximas compilaciones del workflow utilizan la configuración pública del piloto y adjuntan source-commit.json con el commit y la ejecución. La demo web sigue utilizando datos ficticios. Cámara QR: iOS/Android; Windows admite código manual o lector de teclado. Las plataformas no soportadas no muestran una cámara inexistente.


## Estado actual · copias y HTTP

Las pruebas de Auth/Storage HTTP están aprobadas en Supabase, con cuentas ficticias ya retiradas y servicio temporal desactivado. No acreditan funcionamiento del selector, cámara ni inicio de sesión en clientes nativos. Las copias nuevas usan `.tfpart`; consulta COPIAS_Y_RECUPERACION.md. La prueba local de 36 MiB supera el antiguo límite de 32 MiB.

Run 37543505529, commit 6d8fbae: Windows con instalador, Android debug e iOS simulador compilados y descargados/verificados. Incluyen CSV. Son anteriores a la descarga privada por POST y a las copias divididas, y deben actualizarse antes del piloto conectado. Las nuevas compilaciones adjuntarán su commit exacto. No se entrega una app para macOS.

## Evidencia actual · 7 de octubre

Los paquetes Windows/Android/iOS del commit 73e5e66 están descargados y sus SHA-256 coinciden con GitHub. Incluyen copias por partes y descarga privada por POST. Las inspecciones se publicaron en f9aeed3; la prueba nativa Windows de esa versión aprobó archivos/credenciales, fotos pendientes y recuperación de la copia bajo otra clave. Su servidor es ficticio. La compilación general se repite después de corregir el formato de una prueba. Se prepara el mismo circuito en simulador iOS alojado, sin aplicación macOS.
