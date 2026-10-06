# TallerFlow · primera entrega 0.1

Una base ejecutable en Flutter y Dart para conectar operarios y oficina. Diseñada en español para un taller en España que sustituye el papel. Incluye demostración, código nativo, esquema de Supabase, pruebas y preparación de compilaciones.

**Esta entrega es un prototipo funcional de parte de la fase 1. No está lista para datos reales ni equivale a la aplicación completa solicitada.** El cierre conectado se bloquea deliberadamente hasta completar y probar la reconciliación entre todos los dispositivos. El portal, la facturación fiscal y la IA todavía no están implementados.

## Abrir la demostración

La demostración para navegador está compilada. Ejecuta `tool/run_demo.command` y abre `http://127.0.0.1:8777`. En el paquete web independiente basta ejecutar `Abrir TallerFlow.command`. Necesita Python 3, presente en este Mac. Si el puerto está ocupado por la vista ya abierta, utiliza esa vista.

Puedes cambiar entre Álex, Lucía, Marta y administrador desde la barra superior. Todos los datos son ficticios. La vista web pierde los cambios al recargar; la aplicación nativa conserva los registros cifrados en el dispositivo. El selector de cuentas solo existe en modo demo. Con Supabase, los permisos proceden del servidor y cada persona inicia sesión con su propia cuenta.

Prueba este recorrido:

1. Abre el Volkswagen Golf y cambia al operario Álex.
2. Inicia y pausa una tarea. El tiempo trabajado aumenta; el facturable sigue en cero.
3. Registra una pieza o una cantidad decimal de aceite y una observación.
4. Termina las tareas autorizadas y registra la comprobación final.
5. Cambia a Marta, revisa los minutos facturables y confirma los consumos.
6. Revisa los avisos e intenta emitir la nota de demostración. Las tareas y cargos sin autorización, los consumos no revisados o la falta de comprobación bloquean el cierre.
7. Abre el Seat León: su ampliación no autorizada permanece fuera de la nota.
8. Crea una recepción: ninguna plantilla autoriza por sí sola una reparación.

## Qué está implementado

- Panel adaptable, búsqueda, filtros de estado y órdenes asignadas según perfil.
- Recepción breve, matrícula normalizada, VIN opcional, cliente, síntomas originales, kilometraje, ubicación y llaves.
- Identificador estable de vehículo: una nueva recepción reutiliza el vehículo registrado por VIN o matrícula y país.
- Tareas con autorización individual, estimación, tiempo trabajado y minutos facturables separados.
- Cronómetro persistente, pausa y tiempo manual con motivo; rechazo de intervalos solapados.
- Varios operarios en el modelo y pruebas; un cronómetro activo por persona.
- Catálogo de ejemplo, cantidades con tres decimales, reserva, consumo, aportación del cliente y devolución parcial al almacén.
- Precios aplicados conservados en cada consumo, cálculos enteros exactos en céntimos y redondeo por línea.
- Autorizaciones registradas por oficina con versión, destinatario, soporte, autor y fecha.
- Observaciones, traspaso de turno, finalización y comprobación final.
- Borrador de nota determinista; revisión, emisión y entrega con saldo pendiente en la demostración local.
- Generación de QR y apertura introduciendo o pegando su código. La lectura con cámara y los enlaces nativos están pendientes.
- Almacén local AES-GCM; clave y sesión en el almacén seguro nativo; guardado atómico con recuperación de una rotación interrumpida.
- Cola persistente para Supabase, identificadores idempotentes, conservación de conflictos y registros tardíos.
- API autenticada de comandos, aislamiento por taller, tablas privadas con RLS, auditoría y ocultación de importes en el servidor.
- Datos ficticios, scripts de pruebas y workflows para Windows, macOS, simulador iOS y Android.

## Qué necesita completar la fase 1 antes del piloto

- Reconciliación y confirmación de todos los dispositivos que descargan una orden antes del cierre. No basta que el móvil de oficina tenga su cola vacía.
- Resolución de conflictos desde oficina, actualización de otros dispositivos mientras existen operaciones pendientes y revisión de registros tardíos.
- Arranque de una sesión conectada sin red: actualmente se exige conexión al abrir una sesión Supabase. Los registros ya abiertos se pueden conservar sin conexión.
- Pantallas de administración de cuentas, tarifas, impuestos, catálogo y plantillas reutilizables. En esta entrega se configuran desde el servidor; la vista de configuración explica el alcance.
- Reasignación de tareas, múltiples tareas nuevas y operarios desde la interfaz, prioridades y bloqueos editables.
- Historial técnico consolidado, cambios de matrícula/propietario y separación completa de documentos por destinatario.
- Descuentos, precios revisables con motivo, excepciones justificadas de consumo sin cobro y coste/margen estimado.
- Captura de fotografías, QR con cámara y enlaces de apertura nativos.
- Validación de permisos y almacenamiento seguro en dispositivos físicos; pruebas de integración Supabase, exportación y restauración completa.

Las reservas no se convierten automáticamente en consumos en este prototipo. Compras, recepciones parciales, devoluciones al proveedor y liberación de reservas se desarrollarán como almacén avanzado. La vista de vehículos muestra las órdenes descargadas, todavía sin consolidar todo el historial ni ofrecer cambios de propietario.

## Código y documentación

| Carpeta | Contenido |
|---|---|
| `lib/domain` | Reglas, tiempos, permisos locales y cálculos monetarios |
| `lib/data` | Demostración, cifrado, persistencia, Supabase y cola de envío |
| `lib/ui` | Panel, recepción, reparación y revisión de oficina |
| `supabase/migrations` | Tablas privadas y API autenticada |
| `supabase/seed.sql` | Taller y catálogo ficticios, sin contraseñas |
| `test` | Pruebas de reglas, almacenamiento, envío e interfaz |
| `tool/database_test.mjs` | Pruebas ejecutadas en PostgreSQL mediante PGlite |
| `.github/workflows` | Validación y compilaciones nativas preparadas |
| `previews` | Capturas generadas de las pantallas reales de Flutter |
| `docs` | Arquitectura, Mac, alcance, validación y requisitos originales |

Lee [la guía para tu Mac](docs/MAC_Y_PLATAFORMAS.md), [la arquitectura y fases](docs/ARQUITECTURA_Y_FASES.md), [la configuración de Supabase](docs/SUPABASE.md) y [el informe de pruebas](docs/VALIDACION.md).

## Desarrollo

Versión utilizada: Flutter 3.47.6 y Dart 3.13.5. Las dependencias exactas están en `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Para las pruebas de base de datos:

```sh
cd tool
npm install
npm test
```

Estas pruebas no necesitan credenciales y no tocan una base de datos externa. Para regenerar las capturas: `flutter test tool/render_preview_test.dart --update-goldens`.

La tipografía Manrope incluye su licencia OFL. Flutter, sus paquetes y los componentes nativos mantienen sus respectivas licencias.
