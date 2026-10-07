# Agenda de operarios y elevadores

Oficina reserva citas o indisponibilidades con varios operarios, elevador opcional y una orden del taller opcional. Administración configura y retira elevadores. No se puede retirar un elevador con reservas futuras; primero hay que reasignarlas o cancelarlas. Cada intervalo admite desde un minuto hasta siete días.

Las reservas que comparten operario o elevador no pueden solaparse; dos intervalos consecutivos sí se admiten. La confirmación del servidor usa una revisión común de agenda y conserva el identificador de comando. Una respuesta perdida no duplica citas y un cambio simultáneo requiere revisar el estado actual. Sin conexión, la solicitud queda guardada como pendiente, sin ocupar un horario confirmado.

La reprogramación conserva versiones anteriores. Finalizar o cancelar añade una evidencia y no elimina la reserva original. Una reserva finalizada necesita una reserva nueva para volver a planificar. Ninguna de estas acciones autoriza reparaciones, factura tiempos ni altera documentos comerciales.

Los operarios ven sus citas. Las evidencias internas, cambios previos e identificadores de reparaciones no asignadas quedan fuera de su vista. Oficina ve el conjunto del taller; los talleres permanecen aislados.

Las horas se introducen como 08/10/2026 09:00. Se elige Península/Baleares o Canarias, independientemente de la zona del dispositivo. Los cambios de horario se resuelven con la base IANA incluida en [timezone 0.11.1](https://pub.dev/packages/timezone), licencia BSD-2-Clause. Una hora inexistente se rechaza; una hora repetida exige escoger la primera o segunda aparición. Se guarda el instante UTC. No se han confirmado otras zonas del taller ni equipos físicos.

La copia completa usa formato 11 e incluye agenda, versiones, auditoría y recibos de comandos. La recuperación independiente local conserva todo el conjunto, rechaza referencias a otro taller y mantiene inactivos los enlaces antiguos del portal. Las copias 2–10 siguen admitidas. Para restaurar una copia nueva, el destino necesita todas las migraciones.

Validación: trece pruebas Flutter específicas, doce PostgreSQL específicas, recuperación con dieciocho comprobaciones generales y dieciocho SQL alojadas en el proyecto principal, con Auth sintético y reversión completa. No acreditan uso nativo ni Auth HTTP. La migración al proyecto de recuperación qnbgbgumvxmmipjlkcgb está bloqueada por revisión automática hasta recibir autorización específica del destino.
