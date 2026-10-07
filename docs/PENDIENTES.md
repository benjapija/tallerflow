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
| Supabase alojado | Conectado, quince migraciones y funciones de altas/fotos aplicadas | Proyecto gpseuqmzbazifmkhjyby, plan Free; cuenta ramirezbroja013@gmail.com vinculada como administradora; cinco cuentas ficticias probaron Auth real y quedaron retiradas; falta iniciar sesión personalmente desde cliente nativo |
| iOS/Android | Compilación en GitHub aprobada | Xcode 27 instalado y cuenta Apple conectada; Android Studio instalado y herramientas verificadas; licencias del SDK pendientes; llavero y recuperación iOS simulador comprobados con servidor ficticio; equipos físicos pendientes |
| Aplicación macOS | Fuera del alcance | Retirada por petición del usuario el 6 de octubre; el Mac sigue como equipo de desarrollo |
| Windows | Compilación, instalador y circuito nativo remoto aprobados parcialmente | Dos procesos reales con cifrado, credenciales, fotos pendientes y recuperación de partes en Actions; falta instalación manual y cuentas Supabase reales desde la app |
| Inspecciones configurables | Implementadas: 6 Flutter, 8 PostgreSQL local y 10 SQL alojadas | Versiones y evidencias conservadas; selección humana del resultado; falta uso manual nativo; recorrido HTTP probado en la recuperación entre proyectos |
| Presupuestos y autorizaciones versionados | Integrados con órdenes, persistencia, servidor y oficina; pruebas locales y SQL alojado aprobadas | Decisiones por partida, versiones inmutables, impuestos y copias; falta HTTP de presupuestos con Auth real, uso nativo de sus pantallas y portal del destinatario |
| Portal cliente | Pendiente tras fase 1 | HTTPS y verificación/revocación del destinatario |
| Cobros y entrega con saldo pendiente | Implementados y probados localmente y por SQL alojado | Pagos parciales, devoluciones vinculadas, saldo separado y entrega a crédito; ocho pruebas Flutter y diez SQL por proyecto; faltan Auth HTTP y uso manual nativo |
| Compras, almacén, garantías y PDF | En desarrollo | PDF continúa; pedidos manuales, recepciones parciales y garantías pendientes; APIs de proveedores cuando se concreten |
| IA técnica y administrativa | Pendiente | OpenAI desde servidor, presupuesto de consumo, fuentes autorizadas y revisión humana |
| Cuaderno y biblioteca validados | Pendiente | Desarrollo local independiente de IA |
| Dictado y lectura con cámara | Pendiente | Captura nativa y proveedor cuando haya servicio externo |
| Agenda, mantenimiento y flotas | Pendiente | Desarrollo local tras prioridades anteriores |
| Integraciones externas | Proveedores por concretar | Documentación técnica, diagnosis, recambios y servicios necesarios |
| Facturación fiscal | Requisitos por concretar | Datos y obligaciones aplicables del taller español; validación del módulo |

Las dependencias externas detienen únicamente sus tareas. No se generan nuevos prompts de continuación.
