# Entrega 0.2 · resultado y continuidad

Esta entrega implementa el bloque de fiabilidad sobre el proyecto existente. Conserva el recorrido de taller y las reglas anteriores; no incorpora IA, portal, cobros ni facturación fiscal.

| Prioridad solicitada | Implementado | Probado | Pendiente externo |
|---|---|---|---|
| Reapertura offline | Caché cifrada antes de consultar perfil; permisos locales de 24 h y bloqueo por reloj/revocación | Clientes y almacenes de pruebas | Auth y reinicio físico nativos |
| Sincronización con pendientes | Base remota más proyección local; recibos, originales y comandos conservados | Flutter y PostgreSQL | Red real y Supabase alojado |
| Resolución de oficina | Pantalla; aplicar corrección válida o conservar sin aplicar, con motivo y responsable | PostgreSQL y cliente | Jornada real y casos operativos del taller |
| Cierre entre dispositivos | Inscripciones, revisión, bloqueo persistente, confirmaciones e invalidaciones; emisión atómica | Dos operarios/oficina simulados y PostgreSQL | Tres equipos físicos |
| Retirada/sustitución | Auditoría, vínculo de sesiones, recuperación, fin real de cronómetro y excepción administrativa explícita | PostgreSQL/Auth simulado y cliente | Auth alojado y almacenamiento seguro físico |
| Inmutabilidad | Protección de documentos e instantáneas; incidencias tardías sin alterar originales | PostgreSQL y simulación | Procedimiento completo de documentos correctivos, fuera de este bloque |

## Evidencias entregadas

27 pruebas Flutter y 44 comprobaciones PostgreSQL aprobadas, análisis limpio, demo web compilada y capturas generadas. Consulta `VALIDACION.md` y `../evidence/`. Los resultados no acreditan una instalación nativa ni un sistema listo para datos reales.

El código añade la migración `202610060002_reliability.sql`, política de sesión, reconciliación del cliente, controles de oficina y simulación de tres dispositivos. Ambas migraciones se ejecutan en las pruebas de regresión y fiabilidad.

## Siguiente avance recomendado

Conectar un Supabase de pruebas y realizar el recorrido en dispositivos nativos. Desde Mac habrá que completar Xcode y herramientas Android; para Windows, disponer del repositorio GitHub y un Windows remoto. No se han creado cuentas externas ni usado credenciales de esos servicios.

## Resto de fase 1

- Administración de personas/permisos, tarifas/impuestos, catálogo y plantillas reutilizables, con auditoría de producto.
- Edición y reasignación completa de tareas, varios operarios, prioridades y bloqueos desde la interfaz.
- Historial consolidado; cambio de matrícula/propietario con privacidad de documentos y datos personales anteriores.
- Descuentos, revisión de precios con motivo, consumos sin cobro justificados y coste/margen estimado.
- Fotografías/Storage privado, QR por cámara y enlaces nativos.
- Exportación y recuperación completas, validación alojada y jornada en todas las plataformas.

Completar estas funciones y validar el sistema es necesario antes de un piloto con datos reales. La fase 1 no se declara terminada por esta entrega.
