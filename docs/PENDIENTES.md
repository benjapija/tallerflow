# Seguimiento del alcance acordado

Actualizado el 7 de octubre de 2026, 16:44 (España peninsular). Datos ficticios. «Probado» siempre identifica el entorno y no acredita uso físico ni validación fiscal.

| Bloque | Estado comprobado | Pendiente exacto |
|---|---|---|
| Fiabilidad 0.2 | Conservada; reinicios, desconexión, pendientes, conflictos, cierre y retirada probados localmente; recorrido de dos operarios y oficina con Auth real aprobado | Repetir el recorrido desde dispositivos físicos y la cuenta personal |
| Exportación y restauración | Copias cifradas por partes con pendientes, fotos, documentos y auditoría; copia local 36 MiB; recuperación alojada formato 14: once comprobaciones aprobadas | Auth HTTP y recuperación 14 aprobados; selector nativo y recorrido manual; registros locales pendientes comprobados por separado con Flutter y circuito nativo de servidor ficticio |
| Administración y permisos | Usuarios, tarifas, impuestos, catálogo y plantillas implementados; permisos reales por HTTP aprobados | Alta y administración desde la aplicación nativa |
| Tareas | Varios operarios, asignaciones, prioridades y bloqueos implementados y probados; tiempos concurrentes y cierre real por HTTP | Uso manual nativo |
| Historial e identidad | Matrícula/propietario con identidad estable, técnicos conservados y destinatarios originales protegidos; pruebas locales y alojadas | Recorrido manual nativo con cambios de propietario |
| Precios y margen | Revisiones con motivo, reautorización, descuentos antes del IVA, excepciones justificadas y costes implementados y probados | Revisión manual de oficina en la aplicación |
| CSV | Importación de clientes, vehículos y catálogo; vista previa, duplicados, permisos e idempotencia aprobados con Auth real | Selector y apertura del CSV en cliente nativo |
| Fotos, QR y enlaces | Fotos privadas con descarga por POST y permiso revalidado; aislamiento, inmutabilidad y bloqueo de lectura directa aprobados | Cámara y QR físicos, permisos del sistema y apertura por enlace nativo |
| Supabase principal | Plan Free; 27 migraciones lógicas; cuentas/permisos/fotos/portal/IA desplegados | Inicio de sesión personal nativo: ramirezbroja013@gmail.com |
| Supabase recuperación | Autorización específica recibida; cinco migraciones aplicadas, 27 lógicas totales; 83 invariantes SQL revertidas y recuperación formato 14 real aprobadas | Recuperación manual desde aplicaciones; autorización anterior ya resuelta |
| Windows | Aplicación e instalador compilados; circuito anterior entre procesos con credenciales/cifrado/pendientes aprobado en Windows de Actions, servidor ficticio | Equipo Windows con licencia para instalación, selector y uso manual con Supabase |
| iOS | Vision aprobó en simulador lectura, carpeta temporal privada, EXIF, blanco, original externo denegado y archivo ausente | Seis comprobaciones y evidencia adjunta en revisión 6be045d; conectar el iPhone indicado por el usuario, desbloquear/confiar y modo desarrollador; firma personal y cámara/micrófono/QR |
| Android | Licencias aceptadas según el usuario; SDK encontrado. APK compilado; emulador API 35 arranca con partición 2 GiB y espacio liberado | Cinco comprobaciones OCR aprobadas con evidencia en revisión 6be045d. No hay Android físico disponible |
| macOS | Fuera del alcance | Mac exclusivamente desarrollo y revisión de demo web |
| Inspecciones | Versiones, evidencias y resultado humano implementados; pruebas locales, SQL y recuperación HTTP | Uso manual nativo |
| Presupuestos y autorizaciones | Versiones/partidas inmutables; cálculo 4.661 céntimos y decisiones vigentes/reintentos aprobados con Auth real | Pantallas nativas y acceso final del destinatario desde portal publicado |
| Cobros y PDF | Cobro parcial, reversión, abono y exceso rechazado con Auth real; original emitido conservado. PDF ficticios de varias páginas revisados | Selector/impresión/compartir nativo; validación fiscal separada |
| Compras y almacén | Recepción parcial, devolución, coste por permiso, existencias e idempotencia aprobados con Auth real | Uso manual; proveedor para integración externa |
| Garantías | Retornos y reclasificaciones conservan originales y generan autorización nueva; Auth real aprobado | Uso manual nativo |
| Diagnóstico | Cuaderno, correcciones y retiradas mantienen originales; Auth real aprobado | Uso manual nativo y equipo de diagnosis concreto |
| Biblioteca | Publicación humana, versiones y privacidad técnica aprobadas con Auth real | Uso manual y documentación/licencia concreta |
| IA | Preparada y desplegada; nueve Flutter, 14 PostgreSQL, 17 servicios simulados y 14 invariantes alojadas. Persistencia fallida conserva estado; recuperación no reenvía | Desactivada por decisión explícita del usuario; cero solicitudes al proveedor. No solicitar activación ni créditos mientras mantenga esa decisión |
| Dictado y OCR | Captura requiere revisión y confirmación; OCR local restringido a caché/temporal, conserva originales; iOS simulador aprobado | OCR Android en emulador aprobado; cámara y micrófono físicos |
| Agenda | Reservas de varios operarios/elevadores, indisponibilidad y colisiones, idempotencia; Auth real y recuperación formato 14 aprobados | Uso manual nativo |
| Mantenimiento | Fecha/kilometraje, recurrencia y evidencias; Auth real y recuperación formato 14 aprobados | Uso manual nativo |
| Flotas | Vínculos y traslado por propietario con revisión, originales conservados; Auth real y recuperación formato 14 aprobados | Uso manual e integración concreta de flotas |
| Portal HTTPS | Servicio alojado y página implementados; acceso/decisiones/fotos con HTTPS reales previamente aprobados | Sesión Cloudflare abierta y solo TallerFlow seleccionado; confirmar Install & Authorize de GitHub en la pantalla preparada, publicar Pages Free y probar la dirección final |
| Facturación española | Investigación oficial actualizada; presupuestos y notas siguen identificados como documentos de trabajo | Preparación por taller implementada sin activar emisión: titular, territorio, SII, clientes, volumen e impuesto. Cálculo exacto y borradores AEAT locales implementados; registro persistente de ensayo y copia 14 implementados; Auth HTTP, recuperación 14 y peticiones superpuestas aprobados; pendiente interfaz/cola local y XML; después series/cadena fiscales, documentos completos, adaptadores y pruebas oficiales; cada cliente aporta datos fiscales, series y acreditación durante su alta. No declarar terminado el módulo |
| Integraciones | Sin contratos de pago ni proveedores inventados | Proveedor/licencia técnica, marca/modelo de diagnosis, recambios y equipos/API concretos |

## Evidencia actual

243 Flutter anteriores; 11 de copias repetidas; analizador anterior sin incidencias; 295 PostgreSQL/PGlite, 43 servicios simulados y cinco del portal aprobados. En Supabase real se repitieron **15 comprobaciones de fase 1, 12 de módulos, 13 de borradores y once de recuperación formato 14**, con cinco usuarios ficticios por proyecto, JWT reales y datos aislados. Después: cero sesiones, miembros o dispositivos activos en las pruebas, usuarios ficticios bloqueados y ambos servicios temporales retirados (HTTP 410). Ningún usuario personal modificado. Evidencias actuales: fiscal14-hosted-summary, fiscal14-hosted-phase1, fiscal14-hosted-modules, fiscal14-hosted-drafts, fiscal14-hosted-recovery y fiscal14-hosted-cleanup. Las anteriores current-hosted-* conservan el ensayo formato 13.

La ejecución **37624370177**, revisión **6be045dfdc4c5f058f61878aba16a492bf8b782d**, aprobó validación, Windows, Android e iOS. Los tres ZIP están descargados y verificados contra hashes y revisión; OCR Android cinco, iOS seis, JSON y registro adjuntos. Todos los ZIP anteriores, incluido 01576d2, son históricos.

Preparación fiscal por taller: cinco Flutter y doce PostgreSQL incluidas en la batería; doce SQL con rollback en cada Supabase, usando identidades sintéticas. Copia formato 13 y restauración independiente aprobadas. No acredita Auth nativo ni validación fiscal. Compilación común 37624370177, revisión 6be045d: cuatro trabajos aprobados; tres paquetes descargados/verificados, Android OCR cinco e iOS seis.

Las dependencias externas detienen únicamente sus tareas. No se generan prompts de continuación.

Nuevo alcance en 6be045d: núcleo aritmético, desglose de impuestos conservado y adaptador AEAT sin transmisión, con 17 Flutter nuevas y ocho comprobaciones XSD. Batería de 243 Flutter, analizador limpio, compilación web y CI aprobados. Estado de módulos de Configuración corregido. Tres paquetes nativos y demo renovados, descargados y verificados; código de aplicación coincide en 197 archivos. 8877298 y los demás sufijos anteriores son históricos.

Trabajo independiente siguiente: interfaz y cola local del registro de ensayo e integración XML; después series fiscales, rectificaciones y adaptadores oficiales según MOTOR_FISCAL_EN_DESARROLLO.md. Preservar documentos de trabajo y no habilitar emisión. No confundir estos pendientes de desarrollo con dependencias personales.

Cuota observada tras run 26: 342,7 minutos gratuitos restantes, 0 USD facturables; comprobar antes de nuevas compilaciones. CI advierte acciones con Node 20 y setup-java@v4 obsoletos: actualizar en una revisión posterior y validar sin mezclarla con estos paquetes.

Nuevo avance de servidor: 24 comprobaciones PostgreSQL de borradores, total 295; 16 SQL con rollback en cada Supabase. Copia actual formato 14, recuperación local independiente, contador y original conservados. Huella de integridad propia, distinta de AEAT; emisión/transmisión e IA desactivadas. Cliente nativo y demo 6be045d conservados, sin nueva compilación. REGISTRO_BORRADORES_FISCALES.md distingue implementación de servidor e interfaz pendiente.

Recorridos alojados de esta ejecución: **51 HTTP**, 15 fase 1 + 12 módulos + 13 borradores + 11 recuperación 14. Peticiones superpuestas y reintentos conservan un único efecto; no se observan IDs internos de backends. Fotos originales y cuatro registros restaurados; una instalación nueva se mantiene activa tras reintentar restauración. Diez cuentas ficticias bloqueadas, cero sesiones/miembros/dispositivos activos, servicios HTTP 410 y capacidad eliminada. Continúan interfaz/cola y XML, emisión fiscal oficial e intervención física.
