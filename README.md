# TallerFlow · desarrollo de fase 1

Aplicación en español para conectar operarios y oficina y sustituir el papel en un taller de España. Conserva Flutter/Dart, Supabase y las aplicaciones previstas para iOS, Android y Windows, con macOS para desarrollo y revisión de oficina.

**El proyecto está en desarrollo y todavía no completa la fase 1 ni está preparado para datos reales.** La base 0.2 se conserva. Se han añadido copias portátiles cifradas, administración y organización de tareas. Las cinco primeras migraciones y el servicio de alta de cuentas están instalados en Supabase Free; el acceso con Auth y el funcionamiento nativo siguen pendientes de pruebas completas.

Estado vivo: [PENDIENTES.md](docs/PENDIENTES.md).

## Probar desde tu Mac

La demostración está compilada para navegador. Abre el paquete `TallerFlow-0.2-demo-web.zip`, descomprímelo y ejecuta **Abrir TallerFlow.command**. Utiliza Python 3 y abre `http://127.0.0.1:8777/`. Si ya tienes esa demo abierta, recarga la página para cargar la versión nueva.

En **Configuración → Probar dos móviles y oficina** puedes alternar entre Álex, Lucía y oficina/administrador y desconectar cada dispositivo por separado. Es un servidor simulado en memoria, con datos ficticios; al salir o recargar se reinicia. No conecta a Supabase ni acredita una instalación real.

Para comprobar rápidamente el cierre:

1. En la simulación, abre **Renault Kangoo** desde oficina y pulsa **Solicitar o renovar cierre**.
2. Confirma oficina con **Sincronizado: bloquear y confirmar**. El cierre seguirá bloqueado.
3. Cambia a cada móvil, actualízalo, abre la misma reparación y confirma su dispositivo.
4. Vuelve a oficina y actualiza. Con los tres confirmados y las comprobaciones completas se habilita **Emitir nota**.
5. Repite dejando un móvil desconectado: su ausencia impide el cierre. Renovar la solicitud invalida las confirmaciones anteriores.

La guía [FIABILIDAD_Y_PRUEBA_MAC.md](docs/FIABILIDAD_Y_PRUEBA_MAC.md) explica conflictos, recuperación, sustitución y las pruebas pendientes.

## Base de fiabilidad 0.2

- Reapertura de una cuenta previamente validada desde su caché cifrada, sin consultar primero el servidor. Permisos locales con vigencia de 24 horas, comprobación de reloj y revalidación al recuperar conexión.
- Recepción de cambios remotos aunque haya registros locales pendientes. Reconstrucción sobre la base del servidor, conservación de originales y reintentos sin cambiar sus identificadores.
- Pantalla de oficina para conflictos e incidencias: aplicar una corrección vinculada cuando sea válida o conservar el registro sin aplicarlo, con responsable y motivo.
- Dispositivos inscritos por orden, solicitudes de cierre por revisión, bloqueo local persistente antes de confirmar y emisión transaccional con todos los dispositivos reconciliados.
- Retirada con motivo y auditoría; invalida cierres y bloquea las sesiones vinculadas al dispositivo. Sustituirlo requiere un inicio de sesión nuevo. La retirada no acredita sincronización.
- Recuperación de registros de dispositivos retirados y de recepciones aún no subidas. Cronómetros perdidos requieren registrar su hora real de fin con soporte humano.
- Documentos inmutables, incidencias tardías y excepciones de cierre exclusivamente administrativas, explícitas y conservadas en la nota.
- Simulación de dos móviles y oficina utilizando las pantallas y el controlador reales de Flutter.

La recepción, tareas, tiempos estimados/trabajados/facturables separados, catálogo, cantidades decimales, reservas, consumos, devoluciones, autorizaciones manuales y notas deterministas de 0.1 se conservan. La nota **no es una factura fiscal**. IA, portal y pagos siguen fuera de esta entrega.

## Pruebas y límites

- Analizador Flutter sin errores ni avisos.
- 42 pruebas Flutter aprobadas: fiabilidad, copias cifradas, administración, tareas y recuperación del alta sin guardar contraseñas.
- 77 comprobaciones PostgreSQL/PGlite aprobadas aplicando las cinco migraciones; 6 pruebas de la función de alta con Auth simulado.
- 17 comprobaciones de SQL alojado en Supabase aprobadas con identidades ficticias y recuperación completa de sus transacciones. No son inicios de sesión reales.
- GitHub Actions ha validado el código del primer punto de control y compilado macOS e iOS en simulador. Las restantes compilaciones están en curso; ver evidencias y VALIDACION.md.
- Compilación web y capturas de las pantallas correctas.

Los registros están en `evidence/`. [VALIDACION.md](docs/VALIDACION.md) distingue lo ejecutado de Supabase alojado, los reinicios físicos y las plataformas nativas pendientes. Compilar no demuestra funcionamiento nativo.

## Desarrollo y servidor

Flutter 3.47.6 y Dart 3.13.5, con dependencias fijadas en `pubspec.lock`. En este Mac se conserva el SDK temporal bajo `work/`, fuera del paquete del código. Con Flutter disponible:

```sh
flutter pub get
flutter analyze
flutter test
flutter test tool/render_preview_test.dart --update-goldens
flutter build web --release
```

Pruebas de servidor, sin credenciales externas:

```sh
cd tool
npm install
npm test
```

Para conectar un entorno de pruebas nativo, sigue [SUPABASE.md](docs/SUPABASE.md). Aplica **todas las migraciones en orden** y despliega las funciones indicadas en la guía. Nunca incluyas `service_role`, contraseñas de base de datos o claves privadas en Flutter. La web de esta entrega sigue rechazando acceso a un taller real.

Consulta [ARQUITECTURA_Y_FASES.md](docs/ARQUITECTURA_Y_FASES.md), [MAC_Y_PLATAFORMAS.md](docs/MAC_Y_PLATAFORMAS.md) y [ENTREGA_0_2.md](docs/ENTREGA_0_2.md). Los documentos de 0.1 se conservan en `docs/ARCHIVO_0_1/`; los requisitos originales permanecen en `docs/REQUISITOS_ORIGINALES.txt`.
