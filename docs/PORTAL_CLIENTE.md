# Portal del cliente

Oficina crea el acceso desde una orden con presupuesto vigente, después de verificar personalmente al destinatario original y anotar la evidencia. El enlace y el código son independientes: cópialos y comunícalos por canales separados. TallerFlow no envía mensajes automáticamente. Ambos se muestran una vez; no se guardan en claro. Si se pierde esa pantalla, revoca el acceso y crea uno nuevo.

Cada acceso dura como máximo siete días y contiene únicamente las fotos y documentos que oficina seleccione expresamente. La selección inicial está vacía. El destinatario consulta el presupuesto exacto y decide cada partida; la evidencia identifica una decisión del cliente. Cambiar presupuesto o propietario impide nuevas decisiones con el acceso antiguo. Revocación, cierre de la cuenta emisora y recuperación del taller desactivan el acceso. Cinco códigos incorrectos bloquean ese acceso.

El cliente recibe únicamente el contenido permitido. No se entregan costes, márgenes, notas internas ni datos de otros propietarios. Las fotos se verifican y se leen mediante la función privada; no hay enlaces públicos de Storage. La consulta de documentos conserva destinatario e importes originales. No constituye una factura fiscal.

## Publicación gratuita pendiente

El cliente estático está en portal-client/. Puede publicarse en Cloudflare Pages Free, con SSL, sin servidor propio ni npm. Falta iniciar sesión personalmente en https://dash.cloudflare.com/. Después se conecta el repositorio privado benjapija/tallerflow; directorio de salida portal-client, sin comando de compilación. No habilitar servicios de pago. El archivo _headers define la política de seguridad para ese alojamiento. Las condiciones y acceso personal deben completarlos el titular de la cuenta.

La función workshop-portal está desplegada en los dos proyectos Supabase Free. El app.mjs publicado apunta al principal gpseuqmzbazifmkhjyby. No contiene claves administrativas. Si se publica una recuperación, cambiar el endpoint al proyecto nuevo, mantener las migraciones y desplegar la función. En TallerFlow, administración configura la URL HTTPS definitiva antes de crear enlaces.

## Comprobaciones y límites

Cinco pruebas Flutter; trece reglas PostgreSQL específicas del portal; ocho pruebas simuladas del servicio y cinco del cliente; quince SQL alojadas por proyecto y cuatro HTTP reales de denegación por proyecto. La copia/restauración también cubre concesiones y recibos, con enlaces antiguos inactivos. El navegador ficticio reprodujo una respuesta perdida y reintento conservando la primera decisión. El acceso válido, las fotos y decisiones por HTTP contra Supabase y el portal HTTPS público siguen pendientes. No usar datos personales del piloto hasta completar esas comprobaciones.
