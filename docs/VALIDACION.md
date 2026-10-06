# Validación actual · fase 1 en desarrollo

6 de octubre de 2026. Datos ficticios. Flutter 3.47.6 / Dart 3.13.5. Los registros de 0.2 permanecen en evidence y en su entrega original.

| Entorno | Resultado ejecutado | Límite |
|---|---|---|
| Flutter local | 42 pruebas; analizador sin incidencias | No acredita plugins ni equipos físicos |
| PostgreSQL/PGlite | 15 regresión + 29 fiabilidad + 10 copias + 16 gestión + 7 altas = 77 | Auth y sesiones simulados |
| Función de alta | 6 pruebas con API Auth simulada | No crea usuarios reales durante estas pruebas |
| Supabase alojado | Cinco migraciones y función workshop-members desplegadas; 10 pruebas de circuito + 7 de altas | Identidades SQL ficticias; se revierte cada transacción |
| Protección de función alojada | Petición sin autorización devuelve 401 | Comprueba denegación, no un alta autenticada |
| GitHub Actions #1 | Validación aprobada; compilaciones Apple correctas; otros trabajos en curso | Commit c6f9c09; contiene 38 pruebas Flutter y 69 SQL, anteriores al nuevo servicio de altas |
| Uso nativo | Pendiente | Generar un ejecutable no demuestra su funcionamiento |
| Auth real | Pendiente de confirmar correo administrador y probar inicio de sesión | No se conocen ni se guardan contraseñas del usuario |

Evidencias actuales: `flutter-tests-current.txt`, `analyze-current.txt`, `postgres-all-current.txt`, `hosted-database-validation.json`, `account-provisioning-validation.json`, `edge-unauthorized-hosted.txt` y la captura de GitHub. Las migraciones 001–005 se aplican en los bancos de pruebas locales.

Las copias incluyen estado de servidor, documentos inmutables, auditoría, sesiones históricas, cierres, solicitudes de cuentas y el estado local pendiente. El archivo portable está cifrado. Las contraseñas y los tokens Auth se excluyen. La recuperación en otra base requiere las identidades Auth originales; fotografías y copias grandes se incorporarán junto con Storage. Estos límites impiden considerar terminada la recuperación completa.

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

Prueba real entre cuentas de operario y oficina, dispositivos nativos, pérdida de conexión, suspensión/reinicio, permisos de cámara, almacenamiento seguro y recuperación de archivos. El Mac solo tiene herramientas de línea de comandos; Xcode completo y SDK Android no están confirmados. Las compilaciones Apple en GitHub permiten preparar ejecutables sin dar por instalada ninguna de estas herramientas en el Mac del usuario. Windows necesita un entorno remoto accesible y licenciado para instalación y uso.

Historial/propietarios, precios y excepciones, fotos/QR, y fases siguientes siguen abiertos en PENDIENTES.md. Los datos fiscales y las fuentes técnicas requieren confirmación antes de completar sus módulos.
