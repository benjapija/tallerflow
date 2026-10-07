# Referencia actual · 7 de octubre de 2026

El Mac es exclusivamente desarrollo y demo web; no se entrega app macOS. La demo usa datos ficticios y no inicia sesión en el taller alojado.

IA y corrección de carpetas privadas iOS publicadas. CI 37610877432 (01576d2) aprobó Windows/Android/iOS y OCR Android cinco/iOS seis, con evidencia adjunta. Los tres ZIP 01576d2 están descargados y verificados. Se prepara otro juego común con preparación fiscal por taller. Los anteriores son históricos; prevalecen evidence/package-checkpoints.json y el informe para elegir la entrega vigente.

Android: usuario confirma licencias aceptadas; SDK disponible. iPhone indicado: «iPhone 17 e»; falta conectarlo, confiar en el Mac y modo desarrollador. Windows con licencia para uso manual y entrada personal en la app siguen pendientes. Simulación, compilación e integración HTTP se distinguen de uso físico.

Los apartados siguientes conservan instrucciones e historial de entregas anteriores.

---


# Desarrollo y revisión desde el Mac

El Mac es el equipo de desarrollo. Por petición del usuario del 6 de octubre de 2026 no se entrega una aplicación macOS. Los clientes previstos siguen siendo Windows, Android e iOS; la demostración se revisa en navegador.

## Herramientas comprobadas

Mac Apple Silicon, macOS 27.0.1; Flutter 3.47.6 y Dart 3.13.5 preparados en `../../work/flutter` respecto al proyecto. El SDK temporal no se incluye en el ZIP del código. Xcode 27 está instalado desde Apple y reconoce la cuenta del usuario con un Personal Team. No se ha contratado una membresía Apple. Android Studio está instalado y las herramientas oficiales descargadas/verificadas. El usuario confirmó la aceptación personal de las licencias y el SDK está disponible. El emulador alojado aprobó OCR; el uso físico sigue separado.

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

Las versiones se fijan en `pubspec.lock`. Android mínimo 24 y copias automáticas desactivadas para evitar restaurar un almacén sin su clave; iOS mínimo efectivo 15.5 por la lectura de texto. Las declaraciones de plataforma de los paquetes no sustituyen pruebas de funcionamiento.

Referencias: [Flutter iOS](https://docs.flutter.dev/platform-integration/ios/setup), [Flutter Android](https://docs.flutter.dev/platform-integration/android/setup), [Flutter Windows](https://docs.flutter.dev/platform-integration/windows/building), [instalación Flutter](https://docs.flutter.dev/install/manual), [almacenamiento seguro](https://pub.dev/packages/flutter_secure_storage).

Las próximas compilaciones del workflow utilizan la configuración pública del piloto y adjuntan source-commit.json con el commit y la ejecución. La demo web sigue utilizando datos ficticios. Cámara QR: iOS/Android; Windows admite código manual o lector de teclado. Las plataformas no soportadas no muestran una cámara inexistente.


## Estado actual · copias y HTTP

Las pruebas de Auth/Storage HTTP están aprobadas en Supabase, con cuentas ficticias ya retiradas y servicio temporal desactivado. No acreditan funcionamiento del selector, cámara ni inicio de sesión en clientes nativos. Las copias nuevas usan `.tfpart`; consulta COPIAS_Y_RECUPERACION.md. La prueba local de 36 MiB supera el antiguo límite de 32 MiB.

Run 37543505529, commit 6d8fbae: Windows con instalador, Android debug e iOS simulador compilados y descargados/verificados. Incluyen CSV. Son anteriores a la descarga privada por POST y a las copias divididas, y deben actualizarse antes del piloto conectado. Las nuevas compilaciones adjuntarán su commit exacto. No se entrega una app para macOS.

## Evidencia actual · 7 de octubre

Los paquetes Windows/Android/iOS del commit 73e5e66 están descargados y sus SHA-256 coinciden con GitHub. Incluyen copias por partes y descarga privada por POST. Las inspecciones se publicaron en f9aeed3; la prueba nativa Windows de esa versión aprobó archivos/credenciales, fotos pendientes y recuperación de la copia bajo otra clave. Su servidor es ficticio. La compilación general se repite después de corregir el formato de una prueba. Se prepara el mismo circuito en simulador iOS alojado, sin aplicación macOS.


## Paquetes de inspecciones y pruebas iOS · 7 de octubre

Los ZIP `TallerFlow-Windows-piloto-23d62b8.zip`, `TallerFlow-Android-piloto-23d62b8.zip` y `TallerFlow-iOS-simulador-23d62b8.zip` están en outputs, descargados de la ejecución 37554417241 y verificados contra sus hashes. Windows contiene `installer/TallerFlow-Setup.exe`. Copia el ZIP a un Windows y extrae su contenido antes de ejecutar el instalador. Android es un APK debug de pruebas; iOS contiene una aplicación para simulador. No se entrega una aplicación Mac ni una distribución pública firmada.

El simulador iOS aprobó el guardado y la recuperación entre procesos en 37555896692, con llavero y archivos cifrados reales. Se usa `--no-uninstall` para conservar la instalación y su contenedor. El servidor del ensayo es ficticio. Windows aprobó el circuito equivalente en 37553141586.

El código 1026352 añade presupuestos y decisiones por partida. La demo web local ya está compilada con ellos; los paquetes 23d62b8 todavía no los contienen. La nueva compilación se registra en el informe de avance y sus evidencias cuando termine.

## Paquetes históricos de presupuestos · 7 de octubre

Los tres ZIP c0f8a74 están descargados y verificados contra los SHA-256 de GitHub (ejecución 37558197890). Incluyen presupuestos versionados y la corrección de IVA del catálogo. Sustituyeron a los históricos 23d62b8. Los cobros posteriores todavía no están en esos ZIP. Windows incluye installer/TallerFlow-Setup.exe; Android es APK debug; iOS es solo simulador.

## Paquetes históricos de cobros y PDF · 7 de octubre

Los tres ZIP bc694d8 están descargados y verificados contra los SHA-256 de GitHub (ejecución 37565648080). Incluyen presupuestos, IVA corregido, cobros y PDF. Windows incluye installer/TallerFlow-Setup.exe; Android es APK debug; iOS es solo simulador. Son anteriores a las compras y regresos, incluidos en los paquetes siguientes.

## Paquetes de compras y regresos · 7 de octubre

Los tres ZIP 693ec5a están descargados; SHA-256 y source-commit.json coinciden con GitHub, ejecución 37569128092. Incluyen compras, recepción parcial, devoluciones y regresos por garantía, además de presupuestos, cobros y PDF. Windows incluye installer/TallerFlow-Setup.exe; Android es APK debug; iOS es simulador. El cuaderno del código 620384f está compilándose en 37570655120. La biblioteca posterior está en la demo y en ambos proyectos Free; su compilación se registra al finalizar. No se acredita uso físico ni Auth nativo con estas compilaciones.

## Paquetes verificados actuales

Los ZIP bc86821 corresponden a la ejecución 37571952156, terminada correctamente en Windows, Android e iOS simulador. Sus hashes y source-commit.json coinciden; incluyen la biblioteca validada. Windows contiene installer/TallerFlow-Setup.exe, Android un APK debug e iOS una aplicación de simulador. El portal posterior está en desarrollo publicado por separado y aún requiere compilación nueva. La compilación no acredita uso físico ni inicio de sesión alojado nativo. Los hashes están en evidence/package-checkpoints.json.

## Portal compilado

Los paquetes bab8642, ejecución 37577274243, incluyen la biblioteca y los controles de oficina del portal. Los cuatro trabajos pasaron; sus ZIP se descargaron y verificaron contra SHA-256 y source-commit.json. La agenda posterior está en código y demo; requiere compilación nueva. La página pública del cliente es el directorio portal-client y sigue necesitando alojamiento HTTPS y validación con acceso válido.

## Paquetes de mantenimiento y avance de captura

Los tres ZIP b83d789 están descargados y verificados contra SHA-256 y source-commit.json, ejecución 37582607709. Incluyen agenda y mantenimiento. Flotas y captura se publicaron en 90b6478; ejecución 37586489010 aprobó validación, Windows y Android, pero falló iOS al enlazar Pods_Runner. No sustituir el paquete iOS verificado hasta aprobar su reparación. La interfaz del cliente sigue pendiente de publicar en HTTPS; su servicio alojado ya probó acceso válido, decisión y revocación con datos ficticios. Ninguna compilación acredita cámara física ni Auth desde aplicación nativa.
