# Portal del cliente

Oficina crea el acceso desde una orden con presupuesto vigente, después de verificar personalmente al destinatario original y anotar la evidencia. El enlace y el código son independientes: cópialos y comunícalos por canales separados. TallerFlow no envía mensajes automáticamente. Ambos se muestran una vez; no se guardan en claro. Si se pierde esa pantalla, revoca el acceso y crea uno nuevo.

Cada acceso dura como máximo siete días y contiene únicamente las fotos y documentos que oficina seleccione expresamente. La selección inicial está vacía. El destinatario consulta el presupuesto exacto y decide cada partida; la evidencia identifica una decisión del cliente. Cambiar presupuesto o propietario impide nuevas decisiones con el acceso antiguo. Revocación, cierre de la cuenta emisora y recuperación del taller desactivan el acceso. Cinco códigos incorrectos bloquean ese acceso.

El cliente recibe únicamente el contenido permitido. No se entregan costes, márgenes, notas internas ni datos de otros propietarios. Las fotos se verifican y se leen mediante la función privada; no hay enlaces públicos de Storage. La consulta de documentos conserva destinatario e importes originales. No constituye una factura fiscal.

## Publicación HTTPS gratuita comprobada

Portal publicado en https://tallerflow.pages.dev/, desde el repositorio privado benjapija/tallerflow, rama main y directorio portal-client, sin comando de compilación. El titular confirmó acceso exclusivamente a ese repositorio. Solo se publica esa carpeta estática; no contiene claves administrativas. Siete controles HTTPS comprueban entrega y cabeceras de seguridad (_headers). Un acceso sin enlace privado queda bloqueado. El recorrido positivo del navegador se registra por separado.

Administración configura https://tallerflow.pages.dev/ como portalBaseUrl en TallerFlow antes de generar accesos. No enviar enlaces automáticamente. Pages Free se mantiene sin contratar planes; una publicación estática no acredita inicio de sesión nativo de oficina ni uso físico.

La función workshop-portal está desplegada en los dos proyectos Supabase Free. El app.mjs publicado apunta al principal gpseuqmzbazifmkhjyby. No contiene claves administrativas. Si se publica una recuperación, cambiar el endpoint al proyecto nuevo, mantener las migraciones y desplegar la función. En TallerFlow, administración configura la URL HTTPS definitiva antes de crear enlaces.

## Comprobaciones y límites

Cinco pruebas Flutter; catorce reglas PostgreSQL específicas; ocho pruebas simuladas del servicio y cinco del cliente; dieciséis SQL alojadas en el principal y quince históricas en recuperación. Diez comprobaciones nuevas contra HTTPS real prueban lectura válida, ausencia de campos internos, código incorrecto, aceptar/rechazar partidas diferentes, reintento sin duplicar, rechazo de identidad reutilizada, consulta posterior, foto no seleccionada y revocación. La preparación de la orden se hizo mediante SQL con identidades ficticias bloqueadas, sin sesiones ni dispositivos activos. No acredita inicio de sesión de oficina desde aplicación nativa.

Una comprobación adicional confirmó que retirar la cuenta emisora deniega el enlace. La prueba positiva encontró que la respuesta de las decisiones incluía identificadores internos de tarea: la migración 20261007072800_portal_decision_projection.sql los elimina de la respuesta y conserva el registro original del taller. Tres invariantes SQL comprueban un único recibo, autorización independiente y presupuesto original intacto. Al terminar quedan cero enlaces, miembros, dispositivos y sesiones activos del ensayo; los secretos temporales se retiraron de work.

La copia/restauración cubre concesiones y recibos, con enlaces antiguos inactivos. El navegador ficticio reprodujo respuesta perdida y reintento. Permanecen pendientes fotos seleccionadas por HTTP y uso nativo/físico. La página está publicada; consultar cloudflare-pages-https.json y el informe de recorrido de navegador. Evidencias: evidence/portal-valid-http.json, portal-http-invariants.json y portal-hosted-16.json.
