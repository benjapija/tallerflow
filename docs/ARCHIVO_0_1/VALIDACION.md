# Validación de la entrega 0.1

Fecha: 6 de octubre de 2026. Datos ficticios. Mac Apple Silicon, macOS 27.0.1. Flutter 3.47.6 y Dart 3.13.5.

## Resultados ejecutados

| Comprobación | Resultado | Límite de la evidencia |
|---|---|---|
| Analizador Flutter | Sin errores ni avisos | Código, no comportamiento nativo |
| Pruebas Dart/Flutter | 16 pruebas aprobadas | Motor de pruebas, plugins nativos no ejecutados |
| Pruebas PostgreSQL/PGlite | 15 comprobaciones aprobadas | Auth simulado; Supabase alojado no probado |
| Compilación web de demostración | Correcta | No es una compilación nativa |
| Render de panel, reparación y móvil | Correcto | Capturas con datos ficticios |
| Demostración en navegador del Mac | Abre y muestra navegación accesible | Sesión web temporal |
| iOS y macOS nativos | Pendientes | Falta Xcode completo en el Mac |
| Android nativo | Pendiente | Falta Android Studio/SDK en el Mac |
| Windows nativo e instalador | Pendientes | Workflow preparado, no ejecutado |

Los registros resumidos están en `evidence/`. Las capturas están en `previews/`.

## Casos automatizados cubiertos

Flutter: normalización e identidad de vehículo; dos operarios; un cronómetro por persona; orden/tarea no asignada; ampliación no autorizada; tiempo manual solapado; cantidades decimales; reserva separada de consumo; reintento idempotente; devolución parcial/excesiva; precios conservados; cálculo exacto; bloqueos de cierre; conservación de nota ante un registro tardío; restauración de cronómetro; recuperación de rotación atómica interrumpida; serialización de escrituras simultáneas; lectura de almacén cifrado y rechazo de alteración; pérdida de confirmación de servidor; conservación del conflicto; interacción de cronómetro; vista móvil y restricción de oficina.

PostgreSQL: matrícula normalizada y saneamiento de campos de recepción; negación de escritura directa; aislamiento de talleres; negación de lectura anónima; ocultación de dinero al operario; comprobación de identidad y permiso de oficina; un efecto por reintento; sesiones incompatibles y ampliación pendientes; UUID reutilizado con datos distintos; solapamiento manual; precio obtenido del catálogo; cantidad decimal; devolución excesiva; revisión obsoleta de oficina; cierre nube bloqueado; registros tardíos sin cambiar documento; RLS en todas las tablas.

## Guion obligatorio antes de piloto

1. **Dos móviles y una oficina:** descargar una orden, trabajar con operarios distintos, desconectar uno, cerrar/reabrir la app, reiniciar móvil y reconectar. Comparar el diario de cada dispositivo con servidor. Probar doble uso de la cuenta en dos dispositivos.
2. **Tiempos:** estimado/trabajado/facturable separados; pausa no cobrada; solapamiento manual/cronómetro; cambio de fecha, reloj y zona horaria.
3. **Alcance:** tarea aprobada junto a ampliación pendiente. Revisar máximos autorizados y solicitudes nuevas por cambios. Cuando exista portal, probar explícitamente un enlace de versión antigua, expirado, revocado y usado por otro destinatario.
4. **Stock:** litros y envases, reserva/consumo/devolución, recepciones parciales, dos operarios consumiendo la última pieza sin conexión. Debe existir una incidencia revisable, sin doble descuento ni descarte de consumo.
5. **Cierre:** móvil pendiente, cronómetro activo, tarea incompleta, precio ausente, consumo no revisado, exceso autorizado, discrepancia de stock y conflicto. Ninguno debe cerrarse silenciosamente. El prototipo bloquea todo cierre conectado hasta completar el protocolo.
6. **Datos tardíos:** emitir en un entorno de pruebas con el cierre completado y recibir un registro antiguo. Conservar original y nueva incidencia. Probar el procedimiento de corrección trazable.
7. **Privacidad:** taller A nunca recibe datos de B; operario no accede a precios/costes sin permiso; cambio de propietario/matrícula conserva técnica y bloquea facturas y datos anteriores en el portal.
8. **Garantía:** nueva orden vinculada, clasificación humana y original inalterado.
9. **Recuperación:** exportación completa y copia; restaurar base y archivos en otro proyecto de prueba, cotejar cantidades, documentos, autorizaciones, pagos y auditoría. Restaurar también los registros locales pendientes. La prueba de Vault de esta entrega no cubre todo esto.
10. **Windows remoto:** instalador, primera apertura, autenticación, almacenamiento seguro, ratón/teclado, tabulación, escalas 100/125/150/200 %, pérdida de red, suspensión, reinicio, actualización y exportación. Descargar artefacto desde Mac y conservar versión y capturas.
11. **iOS/Android/macOS:** pruebas con dispositivos reales además de simuladores; interrupciones, permisos, cámara/QR cuando se implementen, almacenamiento seguro, recuperación y uso offline.
12. **IA futura:** con IA desactivada, completar jornada. Con IA activa, comprobar fuentes y variante de vehículo, no inventar mediciones/especificaciones ni operaciones; borradores humanos sin tocar importes. Probar retirada de casos reincidentes.

Los casos que corresponden a funciones pendientes se ejecutarán al implementarlas; no se consideran aprobados por estas pruebas iniciales.
