# TallerFlow · gestión del taller

Aplicación en español para conectar operarios y oficina y sustituir el papel en talleres de España, con datos aislados por taller. Conserva Flutter/Dart, Supabase y las aplicaciones previstas para iOS, Android y Windows. El Mac se utiliza para desarrollo y demostración en navegador; por petición del usuario del 6 de octubre no se entrega aplicación macOS.

**El proyecto está en desarrollo y todavía no completa la fase 1 ni está preparado para datos reales.** Conserva la base 0.2, administración, tareas, historial, precios, CSV y fotos privadas. Añade copias cifradas divididas que incluyen fotos y pendientes. Veintisiete migraciones y las funciones de altas/fotos/portal/IA están instaladas en Supabase Free. Se han aprobado 15 comprobaciones reales de Auth/PostgREST/Edge/Storage por HTTP con cinco cuentas ficticias, ya retiradas. La descarga usa un POST privado sin caché y vuelve a comprobar permisos; se deshabilitó la lectura directa de objetos para evitar respuestas antiguas de la CDN. La recuperación alojada previa formato 13 y los recorridos adicionales de módulos ya aprobaron con Auth real; falta completar clientes nativos y cámaras físicas.

Estado vivo: [PENDIENTES.md](docs/PENDIENTES.md). Uso de copias: [COPIAS_Y_RECUPERACION.md](docs/COPIAS_Y_RECUPERACION.md).

## Probar desde tu Mac

La demostración está compilada para navegador. Abre el paquete `TallerFlow-demo-web-6be045d.zip`, descomprímelo y ejecuta **Abrir TallerFlow.command**. Utiliza Python 3 y abre `http://127.0.0.1:8777/`. Si ya tienes esa demo abierta, recarga la página para cargar la versión nueva.

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

La recepción, tareas, tiempos estimados/trabajados/facturables separados, catálogo, cantidades decimales, reservas, consumos, devoluciones, autorizaciones manuales y notas deterministas de 0.1 se conservan. La nota **no es una factura fiscal**. Presupuestos, cobros y exportación PDF están integrados. El portal está implementado y desplegado en Supabase; falta confirmar el permiso preparado en GitHub para Cloudflare y publicar su dirección HTTPS pública; los recorridos HTTPS de acceso válido, decisiones y fotos seleccionadas están aprobados con datos ficticios. La agenda está implementada y desplegada en el principal. Mantenimiento y flotas están implementados y desplegados en el principal. La IA está preparada y desactivada por decisión del usuario; no se activa ni solicita saldo mientras mantenga esa decisión. La preparación fiscal por taller admite distintos titulares, territorios, SII y destinatarios, con motivo y auditoría; no habilita emisión. El cálculo exacto y el adaptador AEAT local están implementados sin emisión; persistencia, series/cadena concurrente, documentos completos, adaptadores y pruebas oficiales siguen pendientes.

## Pruebas y límites

- Analizador Flutter sin errores ni avisos.
- 243 pruebas Flutter aprobadas, con presupuestos, cobros, devoluciones y recuperación sin duplicados. Analizador sin incidencias.
- 295 comprobaciones PostgreSQL/PGlite y 43 de servicios con dependencias simuladas aprobadas; la denegación final de Storage se volvió a comprobar en las 13 de fotos.
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

Pedidos, recepciones parciales y devoluciones manuales integrados en Catálogo. Instrucciones: [Compras y almacén](docs/COMPRAS_Y_ALMACEN.md). Copia de servidor versión 8, compatible con archivos anteriores.

Regresos por garantía, reincidencia o avería diferente, con clasificación humana e historial. Instrucciones: [Garantías y regresos](docs/GARANTIAS_Y_REGRESOS.md).

Cuaderno de diagnóstico con confirmación personal, correcciones y retiradas trazables. [Instrucciones](docs/CUADERNO_DIAGNOSTICO.md).

Biblioteca propia: versiones técnicas, validación humana, retirada con historial y avisos al revisar la evidencia original. Consulta docs/BIBLIOTECA_VALIDADA.md.

Mantenimiento manual disponible en Historial de vehículos: criterios verificados, vencimientos, recurrencia e intervenciones conservadas. Consulta docs/MANTENIMIENTO.md.

Flotas manuales: agrupación, vínculos con propietario original, seguimiento y archivo conservado. Consulta docs/FLOTAS.md.

Dictado y lectura: borradores revisables en recepción, cuaderno y catálogo; lectura local en Android/iOS y códigos de piezas. Uso físico aún pendiente. Consulta docs/CAPTURA_REVISABLE.md.

El asistente conserva fuentes, requiere revisión humana y recupera respuestas sin reenviar generación. Consulta [ASISTENTE_IA.md](docs/ASISTENTE_IA.md). Los resultados y paquetes vigentes están en PENDIENTES.md y evidence/package-checkpoints.json; los apartados históricos no sustituyen esas referencias.

Desarrollo fiscal genérico: cálculo exacto y desglose conservado de notas; adaptador estatal solo local, con huella, QR de pruebas y borradores XML. Emisión desactivada. Estado y pendientes en [MOTOR_FISCAL_EN_DESARROLLO.md](docs/MOTOR_FISCAL_EN_DESARROLLO.md).

Entrega vigente: **6be045d**, GitHub Actions **37624370177**, Windows/Android/iOS simulador aprobados y ZIP verificados. OCR Android cinco e iOS seis; ocho comprobaciones XSD locales. Ninguna emisión fiscal ni uso físico acreditados. Todos los paquetes con otros sufijos son históricos.

Registro persistente de borradores de ensayo en servidor, sin nueva pantalla: series separadas, reintentos, originales y copia formato 14. 24 PostgreSQL nuevas y 16 SQL revertidas por Supabase. Cliente y demo conservan 6be045d; el ZIP de código identifica el nuevo servidor por separado. [Alcance y pendientes](docs/REGISTRO_BORRADORES_FISCALES.md).

Validación alojada formato 14: 51 comprobaciones HTTP con Auth real (15 fase 1, 12 módulos, 13 borradores, 11 recuperación). Fotos/registros originales y nueva instalación tras reintentar preservados. Ambas funciones de ensayo retiradas con HTTP 410; diez cuentas ficticias sin acceso activo. Interfaz de borradores y XML aún pendientes; nunca habilita emisión. Evidencia: evidence/fiscal14-hosted-summary.json.
