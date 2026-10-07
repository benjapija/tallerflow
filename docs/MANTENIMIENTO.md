# Seguimiento de mantenimiento

En Historial de vehículos, oficina puede programar una previsión por fecha, kilometraje o ambos. Se revisa al alcanzar el primero; si falta el kilometraje actual, aparece «Kilometraje por comprobar». Indica el criterio o fuente que has verificado. El programa no inventa intervalos de fabricante.

Una previsión admite intervalos en meses y kilómetros, o una intervención única. Al registrar una intervención, confirma fecha/hora, kilometraje y evidencia; puedes vincular una orden del mismo vehículo. El próximo vencimiento parte de la intervención real, usando el calendario de Península/Baleares o Canarias. Los finales de mes se ajustan al último día válido. Las horas repetidas del cambio de horario requieren elegir su aparición.

Cada cambio conserva versiones, motivos y autor. Las intervenciones mantienen el criterio original, fecha y kilometraje; no sustituyen documentos ni destinatarios. Los planes terminados o pausados requieren un plan nuevo. La información técnica sigue al vehículo cuando cambia matrícula o propietario; los documentos personales conservan sus permisos anteriores.

Sin conexión, la solicitud queda pendiente hasta sincronizar; no se muestra como confirmada antes de recibirla el servidor. Reiniciar o perder una respuesta conserva el identificador y evita duplicados. Dos oficinas con versiones distintas deben actualizar y revisar.

Operarios ven solo el mantenimiento de vehículos asignados, sin el historial de oficina ni referencias a órdenes no asignadas. La edición exige oficina/administrador y una sesión de dispositivo vigente.

## Validación

Ocho pruebas de dominio, cuatro del controlador y una del formulario; doce comprobaciones PostgreSQL locales y dieciocho SQL alojadas en el principal, con Auth sintético y reversión completa. Las copias formato 12 incluyen planes, intervenciones, versiones, auditoría y recibos. Restauración independiente, contenido incoherente y legado formato 11 comprobados; la recuperación alojada del nuevo formato y Auth HTTP/nativo continúan pendientes. El segundo proyecto necesita la autorización específica solicitada. No se han obtenido datos de fabricante ni contratado servicios.
