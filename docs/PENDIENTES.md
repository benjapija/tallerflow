# Seguimiento del alcance acordado

Base: requisitos originales y entrega 0.2. La palabra «probado» identifica el entorno; no acredita un piloto real.

| Prioridad | Estado | Dependencia o siguiente comprobación |
|---|---|---|
| Fiabilidad 0.2 | Implementada y probada localmente | Regresiones locales, SQL alojado y 15 comprobaciones HTTP con Auth real aprobadas; clientes físicos pendientes; circuito nativo Windows e iOS simulador aprobado con servidor ficticio |
| Exportación y restauración completas | Copias por partes y recuperación implementadas y probadas | 36 MiB locales con claves diferentes; diez HTTP reales entre dos proyectos; archivos/clave/fotos nativos Windows e iOS simulador en dos procesos aprobados; selector y piloto manual pendientes |
| Administración, catálogo y plantillas | Edición implementada y probada localmente | Creación desde aplicación y recuperación probadas localmente; servicio desplegado; acceso real por roles comprobado por HTTP; alta desde cliente nativo pendiente |
| Tareas, asignaciones, prioridades y bloqueos | Implementadas y probadas localmente | Circuito de dos operarios y oficina aprobado con JWT reales por HTTP; dispositivos y uso manual pendientes |
| Historial y cambios de propietario/matrícula | Implementados; pruebas locales y 11 alojadas aprobadas | Identidad estable, alias históricos y destinatarios originales protegidos; falta piloto manual nativo y acceso de portal por destinatario |
| Precios, descuentos, excepciones y margen | Implementados; pruebas locales y 10 alojadas aprobadas | Revisión con motivo, reautorización ante aumentos, descuentos antes del IVA y costes de consumos sin cobro; falta piloto manual nativo |
| CSV de clientes, vehículos y catálogo | Implementado; 8 pruebas Flutter, 12 locales SQL y 10 alojadas aprobadas | Vista previa por fila, códigos de cliente, duplicados conservados, auditoría y reintentos; selector nativo y Auth HTTP pendientes |
| Fotos privadas, QR y enlaces nativos | Implementados; pruebas locales y 10 SQL alojadas aprobadas | Descarga privada sin caché, revocación y Storage HTTP comprobados; cámara física y apertura por enlace del sistema pendientes |
| Supabase alojado | Conectado, veintidós migraciones en el principal y funciones de altas/fotos aplicadas | Proyecto gpseuqmzbazifmkhjyby, plan Free; cuenta ramirezbroja013@gmail.com vinculada como administradora; cinco cuentas ficticias probaron Auth real y quedaron retiradas; falta iniciar sesión personalmente desde cliente nativo |
| iOS/Android | Compilación en GitHub aprobada | Xcode 27 instalado y cuenta Apple conectada; Android Studio instalado y herramientas verificadas; licencias del SDK pendientes; llavero y recuperación iOS simulador comprobados con servidor ficticio; equipos físicos pendientes |
| Aplicación macOS | Fuera del alcance | Retirada por petición del usuario el 6 de octubre; el Mac sigue como equipo de desarrollo |
| Windows | Compilación, instalador y circuito nativo remoto aprobados parcialmente | Dos procesos reales con cifrado, credenciales, fotos pendientes y recuperación de partes en Actions; falta instalación manual y cuentas Supabase reales desde la app |
| Inspecciones configurables | Implementadas: 6 Flutter, 8 PostgreSQL local y 10 SQL alojadas | Versiones y evidencias conservadas; selección humana del resultado; falta uso manual nativo; recorrido HTTP probado en la recuperación entre proyectos |
| Presupuestos y autorizaciones versionados | Integrados con órdenes, persistencia, servidor y oficina; pruebas locales y SQL alojado aprobadas | Decisiones por partida, versiones inmutables, impuestos y copias; falta HTTP de presupuestos con Auth real, uso nativo de sus pantallas y portal del destinatario |
| Portal cliente | Implementado y desplegado en ambos proyectos Free | Verificación personal, enlace y código independientes, selección explícita de fotos/documentos, decisiones idempotentes, revocación y restauración sin reactivar enlaces. 15 SQL alojadas por proyecto, ocho denegaciones HTTP reales, cinco Flutter, cinco pruebas del cliente y ocho del servicio. Falta alojamiento HTTPS público y recorrido HTTP de acceso válido; Cloudflare requiere inicio de sesión personal |
| Cobros y entrega con saldo pendiente | Implementados y probados localmente y por SQL alojado | Pagos parciales, devoluciones vinculadas, saldo separado y entrega a crédito; ocho pruebas Flutter y diez SQL por proyecto; faltan Auth HTTP y uso manual nativo |
| PDF de notas y presupuestos | Implementado y probado localmente | Cinco pruebas Flutter; copias de versiones guardadas, destinatario original y notas de varias páginas revisadas; selector y uso físico pendientes |
| Compras y almacén | Pedidos manuales, recepciones parciales y devoluciones al proveedor integrados | Trece Flutter, ocho PostgreSQL y diez SQL alojadas por proyecto; copias completas y pendientes incluidos, legado recuperable. Falta Auth HTTP, uso físico e integraciones de proveedor |
| Garantías y órdenes vinculadas | Regresos y reclasificación con historial implementados | Seis Flutter y ocho PostgreSQL específicos; ocho SQL alojadas por proyecto. Autorizaciones nuevas, destinatario actual y documento anterior conservados. Falta uso nativo y Auth HTTP |
| IA técnica y administrativa | Pendiente | OpenAI desde servidor, presupuesto de consumo, fuentes autorizadas y revisión humana |
| Cuaderno de diagnóstico | Implementado y probado, independiente de IA | Siete Flutter, nueve PostgreSQL y ocho SQL alojadas por proyecto; correcciones y retiradas conservan originales. Auth HTTP y uso físico pendientes |
| Biblioteca de casos validados | Implementada, probada y desplegada | Nueve Flutter, once PostgreSQL y doce SQL alojadas por proyecto; versiones, validación humana, privacidad y retirada; copias versión 9 compatibles con legado. Auth HTTP y uso físico pendientes |
| Dictado y lectura con cámara | Pendiente | Captura nativa y proveedor cuando haya servicio externo |
| Agenda | Implementada, probada y desplegada en el principal | Trece Flutter, doce PostgreSQL específicas y dieciocho SQL alojadas. Reservas múltiples, elevadores, indisponibilidad, solapamientos, historial y pendientes sin conexión. Faltan Auth HTTP, uso nativo y migración de recuperación: revisión automática exige permiso específico para qnbgbgumvxmmipjlkcgb |
| Mantenimiento | Implementado, probado y desplegado en el principal | Trece Flutter, doce PostgreSQL específicas, dieciocho SQL alojadas; previsiones, recurrencia, evidencia, historial, pendientes y copia formato 12. Auth HTTP/nativo y recuperación alojada pendientes |
| Flotas | En desarrollo | Agrupaciones y seguimiento manual; integraciones por confirmar |
| Integraciones externas | Proveedores por concretar | Documentación técnica, diagnosis, recambios y servicios necesarios |
| Facturación fiscal | Requisitos por concretar | Datos y obligaciones aplicables del taller español; validación del módulo |

Las dependencias externas detienen únicamente sus tareas. No se generan nuevos prompts de continuación.
