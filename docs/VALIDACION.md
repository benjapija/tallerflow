# Validación de la entrega 0.2

6 de octubre de 2026. Mac Apple Silicon y datos ficticios. Flutter 3.47.6 / Dart 3.13.5. Las evidencias de 0.1 se conservan; esta tabla corresponde a los registros `*-v02.txt` y `postgres-reliability-tests.txt`.

| Comprobación | Resultado ejecutado | Límite |
|---|---|---|
| Analizador Flutter | Sin errores ni avisos | Análisis del código |
| Pruebas Flutter | 27 aprobadas | Plugins nativos y dispositivos físicos no ejecutados |
| Regresión PostgreSQL | 15 aprobadas con migraciones 001 y 002 | PGlite y Auth simulado |
| Fiabilidad PostgreSQL | 29 aprobadas con migraciones 001 y 002 | PGlite y sesiones/JWT simulados |
| Render de pantallas | 2 pruebas aprobadas, 5 capturas | Motor de pruebas Flutter |
| Compilación web | Correcta | No es compilación nativa |
| Navegador local | Configuración, tres clientes, desconexión de Lucía, bloqueo con 2/3 confirmaciones | Servidor ficticio en memoria |
| iOS / Android / macOS / Windows | Pendientes de prueba funcional | Sin validación nativa |
| Supabase/Auth alojado | Pendiente | No hay proyecto configurado |

La captura `evidence/browser-cierre-v02.png` y el registro `evidence/browser-verification-v02.txt` documentan la revisión en el navegador.

Los 44 casos de PostgreSQL corresponden al esquema actual, no a una ejecución alojada. Las sesiones simuladas no verifican firma JWT, refresh ni comportamiento real de PostgREST/Auth.

## Cobertura del bloque solicitado

- Reapertura desde caché cifrada sin consulta previa; cronómetro y cola conservados al reconstruir el cliente.
- Vencimiento de 24 horas, retroceso de reloj, cuenta incorrecta y revocación, con conservación de pendientes.
- Cambios remotos mientras hay conflictos locales, sin duplicar la proyección ni eliminar originales.
- Recibo perdido, confirmación perdida y reintentos con identificadores estables.
- Fallo de disco antes de confirmar y al guardar un recibo: no se confirma sin bloqueo persistente ni se pierde el comando.
- Dos operarios y oficina; un móvil sin confirmar bloquea emisión.
- Confirmación antigua, cambio durante cierre, incorporación de un equipo nuevo e invalidación de solicitudes.
- Consumos simultáneos de la última existencia: el inválido queda conservado para revisión sin stock negativo.
- Resolución con motivo, responsable, corrección nueva y autor original; recibo de resolución en el equipo de origen.
- Retirada con auditoría, recuperación de registros y recepción nunca subida; sustitución con identidad nueva y sesión nueva.
- Bloqueo de todas las sesiones históricas de un equipo retirado y de una sesión eliminada en Auth, con JWT simulado.
- Fin real y justificado de un cronómetro de equipo perdido, conservando su autor.
- Emisión atómica, total determinista, excepción administrativa identificada e inmutabilidad de fila e instantánea de documento.
- Datos tardíos conservados y resolución que no altera documentos emitidos.
- Permisos, acceso anónimo negado, aislamiento de talleres, precios ocultos al operario y RLS.
- Simulación visible de tres dispositivos, navegación móvil sin desbordamiento y restricciones de oficina.

## Pruebas anteriores conservadas

Se mantienen comprobaciones de matrícula/identidad, autorizaciones individuales, tiempos incompatibles y solapados, cantidades decimales, reservas frente a consumo, devoluciones parciales/excesivas, precios conservados, cálculos, guardado atómico y rechazo de cifrado alterado.

## Pendiente antes de piloto

La reapertura y el reinicio comprobados reconstruyen clientes de pruebas y leen almacenes de prueba; **no son reinicios de móviles reales**. Se requiere una jornada con dos móviles físicos y oficina, Supabase alojado, red interrumpida, clave segura, suspensión, reinicio y recuperación.

En el Mac siguen faltando Xcode completo y Android Studio/SDK en la comprobación de este trabajo. Windows requiere ejecutar la automatización preparada en GitHub y probar instalación y uso en un Windows remoto. No se ha ejecutado esa automatización ni conectado un Windows.

Falta validar exportación y restauración completas. La guía de casos original se conserva en `ARCHIVO_0_1/VALIDACION.md`; sus casos de funciones futuras no se consideran aprobados por esta entrega.
