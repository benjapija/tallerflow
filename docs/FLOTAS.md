# Flotas

Oficina y administración pueden crear agrupaciones, revisar su nombre/responsable e incorporar vehículos con referencia interna y comprobación de pertenencia. Cada vínculo conserva propietario y evidencia originales; pertenecer a una flota no concede acceso a documentos, cambia tarifas ni autoriza presupuestos.

Cada vehículo admite un vínculo activo. Para trasladarlo, retíralo de la flota anterior con motivo y confirma la nueva incorporación. Una flota se archiva después de retirar sus vehículos. Los datos previos, versiones y motivos permanecen consultables en «Ver historial».

La vista reúne órdenes del propietario vinculado y previsiones activas de mantenimiento. Si cambia el propietario, aparece «Revisar vínculo: propietario cambiado», y la vista deja de mostrar sus órdenes/previsiones como vigentes hasta retirar y comprobar el vínculo nuevo. El historial técnico permanece en la ficha; cada documento conserva destinatario y permisos originales. Los operarios no reciben información personal de las flotas.

Las solicitudes sin conexión permanecen pendientes de confirmar por el servidor y sobreviven a reinicios. Un reintento no duplica datos; las versiones antiguas deben actualizarse y revisarse. La copia formato 13 incluye agrupaciones, vínculos, versiones, evidencia, auditoría y recibos; admite formato 12 con flotas vacías.

## Evidencia

Seis pruebas de dominio, cuatro del controlador y una del formulario; diez PostgreSQL locales específicas y dieciocho SQL alojadas en el principal, con Auth sintético y rollback. Restauración en base independiente, propietarios originales, vínculos duplicados, autores ajenos y legado comprobados. Auth HTTP, uso físico y recuperación alojada del formato nuevo pendientes; el segundo proyecto necesita aprobación específica. No se ha contratado telemetría ni integraciones externas.
