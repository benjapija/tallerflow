# Portal del cliente

Oficina crea el acceso desde una orden con presupuesto vigente, después de verificar personalmente al destinatario original y anotar la evidencia. El enlace y el código son independientes: cópialos y comunícalos por canales separados. TallerFlow no envía mensajes automáticamente. Ambos se muestran una vez; no se guardan en claro. Si se pierde esa pantalla, revoca el acceso y crea uno nuevo.

Cada acceso dura como máximo siete días y contiene únicamente las fotos y documentos que oficina seleccione expresamente. La selección inicial está vacía. El destinatario consulta el presupuesto exacto y decide cada partida; la evidencia identifica una decisión del cliente. Cambiar presupuesto o propietario impide nuevas decisiones con el acceso antiguo. Revocación, cierre de la cuenta emisora y recuperación del taller desactivan el acceso. Cinco códigos incorrectos bloquean ese acceso.

El cliente recibe únicamente el contenido permitido. No se entregan costes, márgenes, notas internas ni datos de otros propietarios. Las fotos se verifican y se leen mediante la función privada; no hay enlaces públicos de Storage. La consulta de documentos conserva destinatario e importes originales. No constituye una factura fiscal.

## Publicación gratuita pendiente

El cliente estático está en portal-client/. Puede publicarse en Cloudflare Pages Free, con SSL, sin servidor propio ni npm. Falta iniciar sesión personalmente en https://dash.cloudflare.com/. Después se conecta el repositorio privado benjapija/tallerflow; directorio de salida portal-client, sin comando de compilación. No habilitar servicios de pago. El archivo _headers define la política de seguridad para ese alojamiento. Las condiciones y acceso personal deben completarlos el titular de la cuenta.

La función workshop-portal está desplegada en los dos proyectos Supabase Free. El app.mjs publicado apunta al principal gpseuqmzbazifmkhjyby. No contiene claves administrativas. Si se publica una recuperación, cambiar el endpoint al proyecto nuevo, mantener las migraciones y desplegar la función. En TallerFlow, administración configura la URL HTTPS definitiva antes de crear enlaces.

## Comprobaciones y límites

Cinco pruebas Flutter; catorce reglas PostgreSQL específicas; ocho pruebas simuladas del servicio y cinco del cliente; dieciséis SQL alojadas en el principal y quince históricas en recuperación. Diez comprobaciones nuevas contra HTTPS real prueban lectura válida, ausencia de campos internos, código incorrecto, aceptar/rechazar partidas diferentes, reintento sin duplicar, rechazo de identidad reutilizada, consulta posterior, foto no seleccionada y revocación. La preparación de la orden se hizo mediante SQL con identidades ficticias bloqueadas, sin sesiones ni dispositivos activos. No acredita inicio de sesión de oficina desde aplicación nativa.

Una comprobación adicional confirmó que retirar la cuenta emisora deniega el enlace. La prueba positiva encontró que la respuesta de las decisiones incluía identificadores internos de tarea: la migración 20261007072800_portal_decision_projection.sql los elimina de la respuesta y conserva el registro original del taller. Tres invariantes SQL comprueban un único recibo, autorización independiente y presupuesto original intacto. Al terminar quedan cero enlaces, miembros, dispositivos y sesiones activos del ensayo; los secretos temporales se retiraron de work.

La copia/restauración cubre concesiones y recibos, con enlaces antiguos inactivos. El navegador ficticio reprodujo respuesta perdida y reintento. Permanecen pendientes fotos seleccionadas por HTTP, publicación HTTPS de la interfaz y uso nativo/físico. Evidencias: evidence/portal-valid-http.json, portal-http-invariants.json y portal-hosted-16.json.
