# Copias cifradas y recuperación

Las nuevas copias se guardan en archivos `.tfpart`, numerados y con un identificador común. Conserva **todas las partes de una exportación juntas**, y su contraseña en un lugar distinto del equipo. La contraseña necesita al menos 12 caracteres. Si se cancela guardar una parte, la copia queda incompleta: repite la exportación completa. La restauración admite las partes en cualquier orden, pero rechaza partes ausentes, repetidas, mezcladas, alteradas o truncadas.

En Configuración, «Guardar copia de este equipo» conserva la cuenta, los datos descargados, documentos, auditoría, cronómetros, originales pendientes, comandos y fotografías locales. «Copia completa del taller» añade los datos del servidor y descarga las fotografías originales necesarias; requiere administrador y conexión. Los registros aún no enviados de otros equipos necesitan sus propias copias. Una exportación del servidor no puede conocer registros que siguen solo en otro móvil.

Las fotografías se leen y cifran de una en una; no se acumulan todas en memoria. Se ha comprobado una copia de 36 MiB de fotografías bajo claves de dispositivo diferentes. Cada foto admite hasta 4 MiB, cada parte hasta 20 MiB, el contenido de registros hasta 256 MiB y un conjunto hasta 4096 partes. Estos son límites del formato, no tamaños máximos probados en equipos reales. Se conserva la lectura de copias antiguas `.tfbackup` (32 MiB). PBKDF2-HMAC-SHA256 con 600.000 iteraciones y AES-GCM autentican contenido, orden, identidad y último archivo.

Para recuperar un equipo, selecciona todas las partes, introduce la contraseña y revisa cuenta/taller/pendientes antes de confirmar. Se comprueban hashes y documentos antes de reemplazar el estado. Los archivos verificados pueden prepararse cifrados antes de esa confirmación; un fallo no sustituye los registros actuales. No se restauran sesiones ni permisos de acceso: revalida la cuenta y revisa los registros recuperados.

## Recuperar en otro proyecto Supabase

Es una tarea administrativa separada; todavía falta la prueba alojada completa entre dos proyectos. El procedimiento conserva los UUID originales del taller y de cada cuenta, y nunca recupera contraseñas, claves privadas ni tokens desde una copia de la aplicación.

1. Prepara un proyecto de recuperación vacío y aplica todas las migraciones, además de las funciones `workshop-members` y `workshop-photos` con JWT obligatorio. Mantén `private` fuera de la Data API.
2. Un administrador del servicio debe recrear o verificar las identidades Auth con sus **UUID originales**, mediante la API administrativa del servidor. El correo debe verificarse con su titular; no se deduce de nombres ni se concede acceso por parecido. Utiliza contraseñas nuevas o recuperación de acceso. No reutilices contraseñas antiguas ni exportes `auth.users` hacia la aplicación.
3. Prepara únicamente la pertenencia administradora inicial del taller vacío con el mismo UUID, usando `tool/bootstrap_workshop.sql` adaptado al UUID confirmado. Comprueba el mapeo completo de las cuentas presentes en documentos, auditoría, dispositivos y operaciones antes de restaurar.
4. Compila el cliente con URL/clave publicable del proyecto nuevo y el UUID original del taller. Inicia sesión como la identidad administradora original, con un dispositivo nuevo.
5. Selecciona la copia completa y restaura el servidor. Los equipos históricos quedan retirados y las solicitudes de cierre anteriores se invalidan. El servidor bloquea el trabajo hasta que los archivos originales se hayan subido y verificado. Los reintentos conservan el identificador de restauración.
6. Recupera las copias de cada equipo con la misma identidad personal, renueva su sesión y revisa las incidencias. Comprueba documentos inmutables, auditoría, precios, fotografías, pendientes, revocaciones y aislamiento antes de usar datos reales.

Supabase admite crear cuentas con UUID explícito mediante `auth.admin.createUser`, exclusivamente desde servidor. Se ha comprobado esta creación con cinco cuentas ficticias en el proyecto actual; la recuperación de datos en dos bases PostgreSQL independientes está probada localmente. Esto no sustituye la prueba entre proyectos alojados. Referencia: [migración de identidades Auth](https://supabase.com/docs/guides/platform/migrating-to-supabase/auth0).
