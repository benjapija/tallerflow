# Entorno Supabase de pruebas

No se ha creado un proyecto Supabase ni usado credenciales. Todos los datos de demostración de Flutter son locales y ficticios. La migración se ha ejecutado y probado con PostgreSQL embebido, pero no contra el conjunto alojado Supabase/Auth/Storage.

## Configurar desde el navegador del Mac

1. Crea un proyecto de pruebas en Supabase. Define región, plan y política de copias según las necesidades del taller antes de producción.
2. En SQL Editor ejecuta `supabase/migrations/202610060001_core.sql` y luego `supabase/seed.sql`.
3. La Data API debe exponer `public`; **no añadas `private`** a esquemas expuestos ni a búsquedas extra.
4. En Authentication → Users crea una cuenta individual por persona. No actives registro libre. Copia sus UUID y adapta los ejemplos comentados de `tool/bootstrap_workshop.sql`. El propietario configura administrador, oficina y operarios.
5. Guarda la URL y la clave pública/publishable del proyecto en un archivo local `client-config.json` que no se publique:

```json
{
  "SUPABASE_URL": "https://TU_PROYECTO.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "TU_CLAVE_PUBLICA",
  "WORKSHOP_ID": "a110fc00-0000-4000-8000-000000000001"
}
```

6. Inicia una aplicación **nativa** con `flutter run -d macos --dart-define-from-file=client-config.json`. La vista web de esta entrega rechaza acceso a un taller real. La app nativa muestra inicio de sesión, sin selector de roles demo.
7. Realiza las pruebas de integración, especialmente errores de conexión, permisos y dos móviles. No habilites el piloto con esta entrega parcial.

No pongas en `client-config.json` ni en Flutter una clave `service_role`, la contraseña de base de datos, una clave OpenAI ni otras credenciales privilegiadas. El archivo `.env.example` describe los tres parámetros públicos, pero no se carga automáticamente.

## API preparada

- `my_membership(workshop_id)`: perfil propio, validado por Auth y pertenencia activa.
- `workshop_snapshot(workshop_id)`: órdenes asignadas o de oficina, catálogo y auditoría limitada.
- `apply_operation(workshop_id, device_id, operation)`: comandos permitidos con identidad comprobada, idempotencia, revisión de oficina y registro de incidencias.

`receive`, `start`, `stop`, `manual_time`, `part`, `return`, `note`, `finish_task`, `authorize`, `billable`, `review_parts`, `quality`, `block` y `deliver` están definidos. `issue` devuelve un conflicto hasta completar la reconciliación de todos los dispositivos. `deliver` exige un documento previamente emitido, de modo que el circuito conectado aún no puede cerrarse desde esta versión.

Una operación conserva UUID, actor, orden, revisión base, fecha y carga. El servidor obtiene precios e impuestos de su configuración y catálogo; ignora precios inyectados por el cliente. Las autorizaciones y la revisión de importes son exclusivas de oficina/administrador. Un token de usuario no permite modificar tablas directamente.

Una respuesta `accepted` permite retirar la operación de la cola; `conflict` conserva el registro y detiene el envío para revisión; `late` guarda la incidencia sin alterar un documento emitido. Los errores de transporte conservan el mismo UUID para reintentar.

## Administración inicial

Para esta entrega, tarifas, impuestos, costes, catálogo y pertenencias se configuran mediante el SQL Editor de pruebas. La app todavía no tiene pantallas de edición para esas funciones. Un cambio del catálogo no modifica los consumos existentes. La visibilidad de precio del operario se configura con `members.see_prices`; los costes se limitan al administrador en esta primera política.

El diario de comandos y la auditoría registran los cambios de la app. La configuración manual mediante SQL Editor todavía no dispone de auditoría de producto completa: habrá que añadir comandos administrativos y validarlos antes de producción.

## Recuperación y archivos

La prueba de cifrado verifica lectura de una instantánea con su clave y rechazo de contenido alterado. No sustituye una copia completa de Supabase ni una restauración en otra máquina. Se necesita exportar base de datos, usuarios relevantes, objetos de Storage y metadatos, controlar claves y probar restauración en un proyecto de pruebas. Los archivos/fotografías y sus políticas de acceso aún no se implementan.

Los clientes desconectados no reciben revocaciones instantáneas. El piloto debe definir vigencia de sesiones locales, bloqueo de dispositivo y revalidación; una pérdida de clave no debe llevar a sobrescribir o dar por vacíos los registros.

Referencia: [Row Level Security de Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security) y [Flutter con Supabase](https://supabase.com/docs/guides/getting-started/quickstarts/flutter).
