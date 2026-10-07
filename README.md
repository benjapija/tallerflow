# TallerFlow · desarrollo de fase 1

Aplicación en español para conectar operarios y oficina y sustituir el papel en un taller de España. Conserva Flutter/Dart, Supabase y las aplicaciones previstas para iOS, Android y Windows. El Mac se utiliza para desarrollo y demostración en navegador; por petición del usuario del 6 de octubre no se entrega aplicación macOS.

**El proyecto está en desarrollo y todavía no completa la fase 1 ni está preparado para datos reales.** Conserva la base 0.2, administración, tareas, historial, precios, CSV y fotos privadas. Añade copias cifradas divididas que incluyen fotos y pendientes. Doce migraciones y las funciones de altas/fotos están instaladas en Supabase Free. Se han aprobado 15 comprobaciones reales de Auth/PostgREST/Edge/Storage por HTTP con cinco cuentas ficticias, ya retiradas. La descarga usa un POST privado sin caché y vuelve a comprobar permisos; se deshabilitó la lectura directa de objetos para evitar respuestas antiguas de la CDN. Falta validar este código en clientes nativos, cámaras y recuperación alojada entre proyectos.

Estado vivo: [PENDIENTES.md](docs/PENDIENTES.md). Uso de copias: [COPIAS_Y_RECUPERACION.md](docs/COPIAS_Y_RECUPERACION.md).

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

La recepción, tareas, tiempos estimados/trabajados/facturables separados, catálogo, cantidades decimales, reservas, consumos, devoluciones, autorizaciones manuales y notas deterministas de 0.1 se conservan. La nota **no es una factura fiscal**. Presupuestos, cobros y exportación PDF están integrados. IA, portal, compras avanzadas y garantías continúan pendientes del alcance acordado.

## Pruebas y límites

- Analizador Flutter sin errores ni avisos.
- 122 pruebas Flutter aprobadas, con presupuestos, cobros, devoluciones y recuperación sin duplicados. Analizador sin incidencias.
- 149 comprobaciones PostgreSQL/PGlite y 18 de servicios con dependencias simuladas aprobadas; la denegación final de Storage se volvió a comprobar en las 13 de fotos.
- 58 comprobaciones SQL alojadas históricas con transacciones revertidas y 15 del recorrido HTTP real, con talleres y cuentas ficticios aislados. Las pruebas nativas siguen separadas.
- GitHub Actions #1 compiló Windows e instalador, Android e iOS simulador. También generó un binario macOS antes de retirarse esa plataforma del alcance; no se seguirá distribuyendo.
- Windows remoto en GitHub Actions: dos procesos nativos verifican almacén cifrado, Credential Manager, conservación de dos registros sin conexión, recuperación y un único efecto al reintentar. El servidor es ficticio; instalación manual y Auth real siguen pendientes.
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

Las inspecciones conservan versiones sin cargos automáticos. La recuperación entre dos proyectos Supabase Free pasó diez pruebas HTTP reales con cuentas ficticias, documentos, auditoría y fotos originales; ambas pruebas temporales quedaron retiradas. Windows f9aeed3 pasó fotos cifradas y copia por partes entre dos procesos reales, con servidor ficticio. Consulta docs/VALIDACION.md para las pruebas específicas y sus límites.
