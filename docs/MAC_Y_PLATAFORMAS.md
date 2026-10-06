# Preparación del Mac y plataformas

## Equipo comprobado

El 6 de octubre de 2026: Apple Silicon (`arm64`), macOS 27.0.1, herramientas de línea de comandos de Apple disponibles. No se encontró Xcode completo, Android Studio ni Flutter previamente instalado. Se preparó Flutter 3.47.6/Dart 3.13.5 dentro de la carpeta de trabajo de esta conversación; no se instaló software de pago ni se cambiaron preferencias del sistema.

La compilación web, el analizador y las pruebas de Flutter funcionaron desde este Mac. Las pruebas de interfaz se ejecutaron con el motor de pruebas de Flutter, sin un simulador iOS ni una app nativa macOS. Las pruebas nativas reales siguen pendientes.

## Qué instalar y para qué

| Aplicación en el Mac | Utilidad |
|---|---|
| VS Code con extensión Flutter/Dart | Abrir y editar el código |
| Flutter SDK estable para Apple Silicon | Compilar y probar Flutter/Dart |
| Xcode completo desde Apple | iOS, simulador y aplicación de oficina macOS |
| Android Studio para Apple Silicon | SDK Android, emulador ARM y conexión a móvil |
| CocoaPods cuando lo soliciten los plugins | Integrar los plugins nativos de Apple |
| Navegador | Supabase, GitHub, descargar versiones y portal futuro |
| Windows App u otro cliente remoto | Acceder al Windows de prueba sin desarrollar allí |

Elige Xcode compatible con tu versión concreta de macOS 27.0.1 y los dispositivos de prueba; no se ha comprobado la instalación de esa combinación. La guía oficial requiere Xcode completo para [iOS](https://docs.flutter.dev/platform-integration/ios/setup) y [macOS](https://docs.flutter.dev/platform-integration/macos/setup). La [preparación Android](https://docs.flutter.dev/platform-integration/android/setup) se hace en este mismo Mac.

La carpeta preparada está en `../../work/flutter` respecto del proyecto original. El SDK no se incluye en el ZIP del código. Para una instalación permanente utiliza la [guía oficial de Flutter para Mac](https://docs.flutter.dev/install/manual) y el paquete **Apple Silicon/ARM64**; utiliza la versión fijada 3.47.6 para reproducir esta entrega.

En Terminal, situado en la carpeta TallerFlow:

```sh
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d macos
```

Para iOS, abre el simulador desde Xcode y selecciona su identificador con `flutter run -d ID`. Para iPhone físico, configura equipo de firma y modo de desarrollo en Xcode; la publicación requiere la cuenta de desarrollador y firma correspondientes.

Para Android, abre el administrador de dispositivos de Android Studio, crea un emulador ARM64 y comprueba las licencias del SDK. Usa `flutter run -d ID` para el emulador o un móvil autorizado. No firmes una distribución real con la clave debug de esta entrega.

## Dependencias y compatibilidad

Las versiones efectivamente resueltas se fijan en `pubspec.lock`; que un paquete declare una plataforma no sustituye la prueba nativa.

| Dependencia | iOS | Android | macOS | Windows | Función |
|---|---|---|---|---|---|
| `supabase_flutter` | Declarada | Declarada | Declarada | Declarada | Cuenta y comunicación con servidor |
| `flutter_secure_storage` | Declarada | Declarada | Declarada | Declarada | Clave del almacén y sesión |
| `path_provider` | Declarada | Declarada | Declarada | Declarada | Carpeta privada de aplicación |
| `cryptography` | Dart | Dart | Dart | Dart | Cifrado AES-GCM |
| `qr_flutter` | Flutter | Flutter | Flutter | Flutter | Generación del QR |
| `uuid` | Dart | Dart | Dart | Dart | Identificadores de operaciones |

Documentación de los autores: [Supabase Flutter](https://pub.dev/packages/supabase_flutter), [almacenamiento seguro](https://pub.dev/packages/flutter_secure_storage), [carpetas nativas](https://pub.dev/packages/path_provider), [criptografía](https://pub.dev/packages/cryptography), [QR](https://pub.dev/packages/qr_flutter).

Configuraciones preparadas: Android API mínima 24 e Internet; copias automáticas Android desactivadas para no restaurar un almacén sin su clave; red saliente y Keychain en macOS; entitlement de Keychain en iOS. Proyecto macOS mínimo 12.0 y plugin seguro iOS mínimo 13.0. El mínimo efectivo puede aumentar con Flutter u otros plugins y deberá comprobarse al compilar.

## Windows desde tu Mac

El archivo `.github/workflows/validate-and-build.yml` compila Windows en `windows-2025`, después de validación. Comprueba Visual Studio C++ ATL, construye la aplicación y un instalador Inno Setup. Esa imagen declara ATL en su [inventario oficial](https://raw.githubusercontent.com/actions/runner-images/main/images/windows/Windows2025-Readme.md). No necesitas instalar Visual Studio en tu Mac.

1. Coloca el contenido del proyecto en la raíz de un repositorio GitHub.
2. Entra desde el navegador en Actions → TallerFlow · validar y compilar → Run workflow.
3. Descarga el artefacto `TallerFlow-Windows-demo-N` desde tu Mac.
4. Conserva todo el directorio de la aplicación: el ejecutable necesita DLL, plugins y datos; no copies solo el `.exe`.
5. En el Windows remoto, prueba tanto el instalador como la carpeta portable. Comprueba el runtime Visual C++ requerido por Flutter. El instalador de demostración no incluye todavía firma Authenticode ni distribución del runtime.
6. Sigue el guion de validación y registra versión de Windows, escala de pantalla, resultado y evidencias.

El workflow **no se ha ejecutado** porque no se ha creado ni conectado un repositorio para esta entrega. No hay binarios Windows comprobados ni instalador validado todavía. Compilar correctamente no demostrará que instalación, cifrado, sesión e interfaz funcionen.

La [documentación oficial de Windows](https://docs.flutter.dev/platform-integration/windows/building) explica el paquete nativo y sus componentes. Para producción habrá que firmar, versionar y probar instalación, actualización y desinstalación sin pérdida accidental del almacén.

## Qué vive en la nube

Supabase aloja Auth, PostgreSQL y posteriormente Storage privado y funciones. GitHub Actions proporciona los equipos de compilación. El futuro portal necesita HTTPS y un servicio de verificación de destinatario. OpenAI y la documentación técnica solo se consultarán desde servidor y con conexión. No son necesarios para utilizar los flujos locales de esta demostración.
