# Pendientes del alcance acordado

Corte: **7 de octubre de 2026, 18:02, España peninsular**. Estado contrastado con código y registros locales. Datos ficticios. Windows, Android e iOS son las aplicaciones finales; el Mac solo sirve para desarrollo y demo web. IA real, emisión y transmisión fiscal desactivadas.

## Avance de este corte

La aplicación incorpora **Registro de ensayos**, cola local con identidad conservada, revisión de conflictos y rechazos, y **XML técnicos de ensayo** con conservación cifrada de originales, reinicio y copia. El cliente distingue un pendiente local de un registro confirmado, consulta antes de reenviar y mantiene las instalaciones restauradas congeladas. Oficina/operario no obtienen la administración de ensayos ni una exportación con caché fiscal restringida.

Estos cambios están integrados en la fuente local; su publicación y compilación de la misma revisión siguen pendientes de identificar en la entrega nueva. La última entrega nativa comprobada es **6be045dfdc4c5f058f61878aba16a492bf8b782d**, ejecución **37624370177**: referencia anterior de Windows/Android/iOS simulador, con OCR Android cinco e iOS seis. No contiene la nueva interfaz fiscal. Sus paquetes se conservan identificados como históricos frente al código actual; no existe todavía un paquete de este corte verificado.

El portal se ha publicado en **[tallerflow.pages.dev](https://tallerflow.pages.dev/)** desde `portal-client`, limitado al repositorio autorizado. Se comprobó la página y el rechazo previsto al acceder sin un secreto válido. Falta recorrer una autorización válida y sus permisos desde el sitio publicado y los clientes pertinentes. Esta comprobación negativa no sustituye ese recorrido.

## Fase 1: implementación conservada y validación pendiente

| Bloque | Implementado y comprobado | Pendiente exacto |
| --- | --- | --- |
| Reapertura y sincronización | Pendientes, reintentos, conflictos trazables, cierre coordinado, retirada y originales inmutables; pruebas locales y HTTP alojadas | Repetir desde aplicaciones nativas con Supabase: conexión perdida, reinicio, concurrencia y sesión personal |
| Copia completa y restauración | Cifrado por partes, registros locales pendientes, fotos, documentos y auditoría; formato de servidor 14 y once comprobaciones HTTP de recuperación conservadas | Selector/archivos desde cada plataforma y recuperación manual aislada; la cola/XML nuevos deben probarse desde la entrega nueva |
| Administración | Altas, roles/permisos, tarifas, impuestos, catálogo y plantillas; controles de servidor HTTP comprobados | Alta y cambios efectivos desde la aplicación nativa, incluida retirada del acceso en otra sesión |
| Tareas y asignaciones | Varios operarios, prioridades, bloqueos y tiempos; concurrencia/cierre por HTTP | Recorrido simultáneo de operario A, B y oficina con sesiones nativas independientes |
| Historial del vehículo | Identidad técnica estable, cambios de matrícula/propietario y destinatarios originales protegidos | Revisar búsquedas, órdenes antiguas y privacidad personal en la aplicación nativa |
| Precios y costes | Motivos, descuentos, consumo sin cobro justificado, coste/margen y reautorización; importes originales conservados | Revisión manual de oficina/administración y negativas de operario sin permiso |
| CSV | Clientes, vehículos y catálogo; revisión previa, relaciones, duplicados, permisos e idempotencia | Guardado/apertura/selección real de CSV, cancelación y errores de archivo por plataforma |
| Fotografías privadas | Permiso revalidado, lectura por servicio autorizado, cifrado local, originales y aislamiento; HTTP real previo | Cámara/galería, orientación, cancelación y denegación del sistema; reconexión/reinicio con foto pendiente en clientes reales |
| QR y enlaces | Código/enlace de orden y controles de acceso implementados | Cámara física, arranque en frío/caliente por enlace y negativa de una orden no asignada; Windows según lector disponible |
| Supabase principal | Plan Free y 27 migraciones lógicas; cuentas, permisos y servicios desplegados | Inicio de sesión personal en cliente nativo: **ramirezbroja013@gmail.com**; contraseña solo en la aplicación |
| Supabase recuperación | Permiso específico resuelto, 27 migraciones lógicas y recuperación formato 14 real previa | Restauración manual desde aplicación en destino aislado; no repetir la consulta de autorización ni restaurar sobre datos de uso normal |

## Plataformas y distribución

| Plataforma | Evidencia disponible | Trabajo restante |
| --- | --- | --- |
| Windows | Compilación/instalador anteriores y persistencia entre procesos en Windows de Actions con servidor ficticio | Nueva compilación común, descarga/verificación; instalación y Supabase manual en Windows con licencia. El usuario confirmó que no dispone de Windows |
| Android | Licencias aceptadas; SDK/ADB disponibles; OCR anterior en emulador API 35, cinco comprobaciones | Nueva compilación/OCR y paquetes; recorrido nativo Supabase. ADB del Mac devolvió lista vacía en la consulta posterior; Android físico no disponible para acreditar cámara/micrófono/QR |
| iOS | OCR anterior en simulador: seis comprobaciones, orientación EXIF, temporal privado permitido, ruta externa denegada, blanco y archivo ausente | Nueva compilación de simulador; conectar/desbloquear/confiar el iPhone indicado, firma personal y uso físico. CoreDevice agotó cinco segundos: no permite afirmar ausencia del teléfono |
| Demo web | Entrega anterior identificada; perfiles y servidor ficticios | Regenerar la demo desde la misma fuente de la entrega nueva y verificar metadatos; no acredita Auth real |
| Código y paquetes | Verificador parametrizado preparado; diez comprobaciones adversas y prueba funcional histórica aprobadas | Publicar fuente autorizada, obtener revisión/run, verificar tres ZIP y hashes; actualizar código ZIP, demo e instrucciones sin mezclar entregas |

La cuota observada antes de la siguiente ejecución era **342,7 minutos incluidos y 0 USD facturables**. Es una observación fechada, no saldo garantizado actual. Reconsultar cuota, consumo compartido y almacenamiento antes de lanzar una compilación. Un run completo tiene límites de 15/20/24/25 minutos por trabajo y una planificación conservadora equivalente de 330 minutos; las tarifas/multiplicadores no garantizan por sí solos el consumo incluido. No habilitar sobreconsumo, nuevos planes ni servicios de pago. Los workflows siguen siendo manuales.

## Fases posteriores

| Bloque | Estado de implementación/validación | Pendiente exacto |
| --- | --- | --- |
| Inspecciones | Versiones, evidencias y revisión humana; local y HTTP real previos | Uso manual nativo y selección/captura de evidencias |
| Presupuestos y autorizaciones | Partidas/versiones inmutables, cálculos y autorización de versión concreta; HTTP real previo | Recorrido nativo y autorización válida desde el portal publicado, caducidad y versión nueva |
| Cobros y PDF | Movimientos manuales parciales, reversión, exceso rechazado y documentos originales; HTTP previo y PDF ficticios revisados | Selector, apertura, impresión/compartir por plataforma; no son facturas fiscales ni un cobro bancario |
| Compras y almacén | Recepción parcial, devolución, permisos de costes y existencias/idempotencia; HTTP previo | Recorrido manual; proveedor/API para integración externa concreta |
| Garantías | Retorno/reclasificación conservan originales y requieren autorización nueva; HTTP previo | Recorrido manual nativo y circuito de proveedor concreto |
| Diagnóstico | Cuaderno, hipótesis, resultados, correcciones y retiradas conservados; HTTP previo | Uso nativo y equipo de diagnosis/API identificado para un adaptador real |
| Biblioteca técnica | Versiones, publicación humana y privacidad; HTTP previo | Uso nativo; proveedor y licencia/derechos antes de incorporar documentación externa |
| IA técnica/administrativa | Circuito preparado; fallos de persistencia conservan originales y recuperación no reenvía | **Desactivada por decisión del usuario**; cero llamadas reales. No solicitar claves/créditos ni activarla para completar otros módulos |
| Dictado y lectura | Revisión/confirmación humana; OCR nativo de imágenes ficticias probado en simulación | Cámara y micrófono físicos, permisos/cancelación y flujo nativo completo |
| Agenda y mantenimiento | Reservas/colisiones, recurrencia por fecha/km y evidencias; HTTP y recuperación previos | Uso manual nativo y datos/adaptadores concretos cuando el cliente los requiera |
| Flotas | Vínculos/traslado con revisión y originales conservados; HTTP previo | Uso nativo, privacidad entre propietarios e integración de proveedor concreta |
| Portal HTTPS | Página publicada; acceso sin secreto rechazado; servicio alojado con HTTP real previo | Recorrido positivo de destinatario autorizado desde URL final y versión/permiso/foto correctos |

## Trabajo fiscal que continúa abierto

| Capa | Implementado | Pendiente |
| --- | --- | --- |
| Preparación y cálculo | Perfiles de taller, territorios, SII declarado, importes exactos y desglose original | Datos/series/acreditación de cada cliente durante su alta; no inferir obligaciones fiscales con un perfil de ensayo |
| Registro persistente de ensayo | Servidor en ambos proyectos; originales, series ENSAYO, recibos, auditoría, cadena, retiradas y recuperación 14; HTTP previo | Continuidad, series/numeración y circuito **fiscal real**, distinto del ensayo |
| Cliente de ensayo | Interfaz, cola cifrada, consulta/reconciliación, UUID/payload exactos, conflictos revisados, permisos y recuperación con dispositivo de origen conservado | Compilación/distribución de la revisión nueva y NativoSupabase; no atribuirle las pruebas HTTP del servidor como uso de la interfaz |
| XML de ensayo | Proyección F1 general desde original confirmado, snapshots/huellas/bytes conservados, copia/reinicio y guardado por selector implementados | Validación nativa del selector y copia; persistencia compartida del XML en servidor todavía no implementada. Hoy queda en almacén local cifrado y copia portable |
| Reglas de documentos | `fiscal_document_rules.dart`: veinte pruebas de dominio para identidades, simplificadas, rectificaciones, subsanación, anticipos, recargos/retenciones y límites; sin emitir | Incorporar contrato persistente, campos SQL, interfaz y proyecciones XML de los nuevos tipos. Correcciones adicionales de fecha/rechazo previo/desglose están en revisión y necesitan su nueva prueba antes de incorporarse al resultado global |
| Adaptadores y aceptación | Huellas/ejemplos y XSD oficiales locales comprobados; no se llamó al servicio fiscal | F2/F3/rectificativas, campos condicionados, territorios/circuitos restantes, certificados/acreditación, transporte/respuestas y pruebas oficiales. No declarar factura fiscal validada |

Las notas, presupuestos y PDF actuales siguen identificados como **documentos de trabajo**. El XML y la huella de un ensayo no acreditan aceptación por Hacienda. Los datos desconocidos de un taller concreto no bloquean el diseño genérico para talleres de España; sí condicionan el alta y la activación acreditada de cada cliente.

## Resultados y límites de este corte

- Última batería global local cerrada: **333 Flutter**, analizador limpio y web release aprobada. Incluye las veinte pruebas nuevas de reglas de documentos; no sumarlas otra vez. Las correcciones en curso no quedan acreditadas hasta repetir sus pruebas y la batería correspondiente.
- **29 suites Node** aprobadas, salida global 0: **295 comprobaciones PostgreSQL/PGlite y tres vectores PostgreSQL independientes de huella**, **43 servicios simulados** y **cinco del portal**. Auth sintético/simulado en esas suites; no son integración alojada.
- **13 comprobaciones VM** de proyección XML y **diez XSD** locales aprobadas. Generación y recuperación de bytes ficticios; sin transporte fiscal.
- Evidencia alojada conservada: **51 HTTP reales** —15 fase 1, 12 módulos, 13 ensayos, once recuperación formato 14— con identidades ficticias y cinco usuarios por proyecto. Peticiones HTTP superpuestas conservan un efecto; no se observaron IDs internos de procesos PostgreSQL. No se repitió esa integración desde la interfaz nueva en este corte.
- Limpieza alojada previa: diez cuentas ficticias bloqueadas; cero sesiones, miembros o dispositivos activos de pruebas; servicios temporales HTTP 410 y capacidad eliminada. Usuarios personales intactos.
- La evidencia de Windows/iOS entre procesos usó servidor ficticio; OCR Android/iOS usó emulador/simulador. **NativoSupabase y uso físico siguen pendientes**, incluyendo cámara, micrófono, QR, enlaces, selector y sesión personal.

Fuentes: `evidence/fiscal14-hosted-summary.json` y sus resultados/limpieza; `evidence/fiscal-confirmed-xml-xsd.json`; `evidence/native-pilot-inventory-20261007.json`; registros locales de la ejecución fiscal-cliente. La revisión fuente y ejecución nueva se completan en el informe de entrega cuando se publiquen y verifiquen, sin asignarles el run histórico.

## Siguiente trabajo e intervenciones

1. Cerrar las correcciones de reglas de documentos, repetir comprobaciones pertinentes y publicar los cambios autorizados.
2. Comprobar cuota gratuita y generar/verificar Windows, Android e iOS desde una revisión común; actualizar paquetes, demo, código e instrucciones. Las compilaciones deben distinguirse del uso nativo y físico.
3. Ejecutar [RECORRIDOS_PILOTO_NATIVO.md](RECORRIDOS_PILOTO_NATIVO.md) con la entrega identificada: sesión personal, permisos, archivos, fotos, QR, presupuestos/cobros, desconexión/cierre y recuperación; conservar los fallos y su evidencia.
4. Continuar campos/contratos/interfaz/XML fiscales, persistencia XML compartida y adaptadores dentro del alcance, sin activar emisión ni IA.

Intervenciones personales limitadas a lo que siga faltando: acceso/firma y avisos del iPhone; contraseña personal introducida en la aplicación; Windows con licencia/acceso para prueba manual; Android físico si se pretende acreditar su captura. Cloudflare ya está autorizado y publicado; licencias Android y autorización específica de recuperación ya resueltas. La herramienta de permisos de archivos todavía no ha confirmado la ampliación necesaria para los tramos nativos que escriban fuera del proyecto: ese límite detiene solo esos tramos.

Integraciones concretas requieren proveedor, licencia, marca/modelo o equipo/API de cada cliente; no se inventan contratos ni se contratan servicios. Una dependencia externa bloquea únicamente su tarea. El proyecto sigue en desarrollo: no está completo ni solo pendiente de intervención personal. No se redactan prompts de continuación.
