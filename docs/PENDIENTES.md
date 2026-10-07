# Seguimiento del alcance acordado

Actualizado el 7 de octubre de 2026, 15:22 (España peninsular). Datos ficticios. «Probado» siempre identifica el entorno y no acredita uso físico ni validación fiscal.

| Bloque | Estado comprobado | Pendiente exacto |
|---|---|---|
| Fiabilidad 0.2 | Conservada; reinicios, desconexión, pendientes, conflictos, cierre y retirada probados localmente; recorrido de dos operarios y oficina con Auth real aprobado | Repetir el recorrido desde dispositivos físicos y la cuenta personal |
| Exportación y restauración | Copias cifradas por partes con pendientes, fotos, documentos y auditoría; copia local 36 MiB; recuperación alojada actual formato 13: nueve comprobaciones aprobadas | Selector nativo y recorrido manual; registros locales pendientes comprobados por separado con Flutter y circuito nativo de servidor ficticio |
| Administración y permisos | Usuarios, tarifas, impuestos, catálogo y plantillas implementados; permisos reales por HTTP aprobados | Alta y administración desde la aplicación nativa |
| Tareas | Varios operarios, asignaciones, prioridades y bloqueos implementados y probados; tiempos concurrentes y cierre real por HTTP | Uso manual nativo |
| Historial e identidad | Matrícula/propietario con identidad estable, técnicos conservados y destinatarios originales protegidos; pruebas locales y alojadas | Recorrido manual nativo con cambios de propietario |
| Precios y margen | Revisiones con motivo, reautorización, descuentos antes del IVA, excepciones justificadas y costes implementados y probados | Revisión manual de oficina en la aplicación |
| CSV | Importación de clientes, vehículos y catálogo; vista previa, duplicados, permisos e idempotencia aprobados con Auth real | Selector y apertura del CSV en cliente nativo |
| Fotos, QR y enlaces | Fotos privadas con descarga por POST y permiso revalidado; aislamiento, inmutabilidad y bloqueo de lectura directa aprobados | Cámara y QR físicos, permisos del sistema y apertura por enlace nativo |
| Supabase principal | Plan Free; 26 migraciones lógicas; cuentas/permisos/fotos/portal/IA desplegados | Inicio de sesión personal nativo: ramirezbroja013@gmail.com |
| Supabase recuperación | Autorización específica recibida; cinco migraciones aplicadas, 26 lógicas totales; 83 invariantes SQL revertidas y recuperación formato 13 real aprobadas | Recuperación manual desde aplicaciones; autorización anterior ya resuelta |
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
| Agenda | Reservas de varios operarios/elevadores, indisponibilidad y colisiones, idempotencia; Auth real y recuperación actual aprobados | Uso manual nativo |
| Mantenimiento | Fecha/kilometraje, recurrencia y evidencias; Auth real y recuperación actual aprobados | Uso manual nativo |
| Flotas | Vínculos y traslado por propietario con revisión, originales conservados; Auth real y recuperación actual aprobados | Uso manual e integración concreta de flotas |
| Portal HTTPS | Servicio alojado y página implementados; acceso/decisiones/fotos con HTTPS reales previamente aprobados | Sesión Cloudflare abierta y solo TallerFlow seleccionado; confirmar Install & Authorize de GitHub en la pantalla preparada, publicar Pages Free y probar la dirección final |
| Facturación española | Investigación oficial actualizada; presupuestos y notas siguen identificados como documentos de trabajo | Preparación por taller implementada sin activar emisión: titular, territorio, SII, clientes, volumen e impuesto. Cálculo exacto y borradores AEAT locales implementados; pendiente persistencia, series, cadena concurrente, documentos completos, adaptadores y pruebas oficiales; cada cliente aporta datos fiscales, series y acreditación durante su alta. No declarar terminado el módulo |
| Integraciones | Sin contratos de pago ni proveedores inventados | Proveedor/licencia técnica, marca/modelo de diagnosis, recambios y equipos/API concretos |

## Evidencia actual

243 Flutter; analizador sin incidencias; 271 PostgreSQL/PGlite, 43 servicios simulados y cinco del portal aprobados. En Supabase real se repitieron **15 comprobaciones de fase 1, 12 de módulos y nueve de recuperación actual**, con cinco usuarios ficticios por proyecto, JWT reales y datos aislados. Después: cero sesiones, miembros o dispositivos activos en las pruebas, usuarios ficticios bloqueados y ambos servicios temporales retirados (HTTP 410). Ningún usuario personal modificado. Evidencias: current-hosted-phase1, current-hosted-modules, current-hosted-recovery, current-hosted-cleanup y current-recovery-schema.

La ejecución **37624370177**, revisión **6be045dfdc4c5f058f61878aba16a492bf8b782d**, aprobó validación, Windows, Android e iOS. Los tres ZIP están descargados y verificados contra hashes y revisión; OCR Android cinco, iOS seis, JSON y registro adjuntos. Todos los ZIP anteriores, incluido 01576d2, son históricos.

Preparación fiscal por taller: cinco Flutter y doce PostgreSQL incluidas en la batería; doce SQL con rollback en cada Supabase, usando identidades sintéticas. Copia formato 13 y restauración independiente aprobadas. No acredita Auth nativo ni validación fiscal. Compilación común 37624370177, revisión 6be045d: cuatro trabajos aprobados; tres paquetes descargados/verificados, Android OCR cinco e iOS seis.

Las dependencias externas detienen únicamente sus tareas. No se generan prompts de continuación.

Nuevo alcance en 6be045d: núcleo aritmético, desglose de impuestos conservado y adaptador AEAT sin transmisión, con 17 Flutter nuevas y ocho comprobaciones XSD. Batería de 243 Flutter, analizador limpio, compilación web y CI aprobados. Estado de módulos de Configuración corregido. Tres paquetes nativos y demo renovados, descargados y verificados; código de aplicación coincide en 197 archivos. 8877298 y los demás sufijos anteriores son históricos.

Trabajo independiente siguiente: persistencia/series/cadena concurrente, rectificaciones y adaptadores oficiales según MOTOR_FISCAL_EN_DESARROLLO.md. Preservar documentos de trabajo y no habilitar emisión. No confundir estos pendientes de desarrollo con dependencias personales.

Cuota observada tras run 26: 342,7 minutos gratuitos restantes, 0 USD facturables; comprobar antes de nuevas compilaciones. CI advierte acciones con Node 20 y setup-java@v4 obsoletos: actualizar en una revisión posterior y validar sin mezclarla con estos paquetes.
