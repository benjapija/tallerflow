# Recorridos del piloto nativo de TallerFlow

Documento de trabajo preparado el 7 de octubre de 2026. Este protocolo permite repetir pruebas desde iOS, Android y Windows y registrar qué se ha observado. Redactar un recorrido no significa haberlo ejecutado. Ninguna casilla de este documento acredita por sí sola una prueba aprobada.

Las plataformas finales son iOS, Android y Windows. El Mac sirve para desarrollo y revisión de la demo web. La IA real, la emisión fiscal y el envío a servicios fiscales siguen desactivados. Los presupuestos, notas y PDF son documentos de trabajo. Se utiliza exclusivamente información ficticia hasta aprobar el piloto.

## 1. Identificar la entrega y el entorno

Antes de instalar, consultar el informe vigente `../INFORME_TALLERFLOW_AVANCE.md` y `../INSTALACION_TALLERFLOW.md`. Los apartados históricos de `VALIDACION.md` conservan fallos y resultados anteriores: su fecha y revisión son parte de la evidencia.

Extraer `source-commit.json` del paquete y anotar su revisión completa, ejecución de GitHub, plataforma y SHA-256 del ZIP. Comparar el SHA-256 con el publicado junto a ese paquete. Conservar juntos ejecutable, bibliotecas, recursos y metadatos. Si Windows, Android e iOS no indican la misma revisión, registrar entregas distintas; no combinar sus resultados como una validación de la revisión actual.

El código local incorpora pantallas de ensayos y XML posteriores al cliente `6be045d`. Para los recorridos P15 y P16 se necesita una entrega que contenga `FiscalDraftsPanel`, `FiscalDraftXmlPanel` y su cola. Si esas pantallas no aparecen, el resultado es «paquete anterior», no un fallo del servidor ni una prueba aprobada. La revisión exacta de la entrega nueva se obtiene de sus metadatos, no de este protocolo.

Registrar también: sistema y versión, modelo, simulador/emulador o equipo físico, proyecto Supabase de pruebas, perfil, identificadores ficticios del caso y hora UTC. No incluir contraseñas, JWT, claves, códigos de portal vigentes, contenido personal ni la frase de la copia en capturas o registros.

### Capas de evidencia

| Capa | Qué comprueba | Qué no acredita |
| --- | --- | --- |
| Widget/Mock | Pantallas, dominio, cola y respuestas simuladas en pruebas automatizadas | Plugins del sistema, Auth alojado, cámara o equipos físicos |
| NativeSimulation | Aplicación o plugins nativos en simulador iOS, emulador Android o entorno Windows de pruebas; indicar si el servidor es ficticio | Uso físico; Supabase real cuando el servidor es ficticio |
| SupabaseHTTP | Auth, RPC, servicios de fotos y recuperación mediante HTTP real | Recorrido de botones, permisos del sistema ni almacenamiento de una aplicación nativa |
| NativoSupabase | Aplicación nativa instalada con cuentas y servicios Supabase reales | Cámara, micrófono o comportamiento físico si se ejecuta en simulador |
| Dispositivo físico | Instalación y recorrido observado en un iPhone, Android o Windows concreto; indicar si utiliza Supabase real | Otras plataformas, revisiones o dispositivos no probados |

Una compilación satisfactoria constituye evidencia de compilación. Para acreditar funcionamiento hacen falta resultados de las capas anteriores. La demo web mantiene un servidor ficticio y datos en memoria; recargarla no simula una recuperación nativa.

### Matriz de partida, sin atribuir resultados nuevos

«Histórica» significa que existe evidencia de una revisión anterior; consultar sus metadatos y cobertura. «Preparada» significa que hay comprobaciones en código cuyo resultado debe leerse en el registro de la ejecución actual. Todos los recorridos manuales de la nueva entrega comienzan pendientes.

| Bloque | Widget/Mock | NativeSimulation | SupabaseHTTP | NativoSupabase | Dispositivo físico |
| --- | --- | --- | --- | --- | --- |
| Acceso, roles, CSV, tareas, precios e historial | Cobertura automatizada; repetir revisión actual | Cobertura parcial histórica | Fase 1, evidencia alojada histórica | Pendiente | Pendiente |
| Archivos privados, fotos, copia y reinicio | Cobertura automatizada | Windows/iOS históricos con servidor ficticio | Fotos y restauración, evidencia alojada histórica | Pendiente | Pendiente |
| OCR, orientación y ruta privada permitida | Cobertura automatizada | Android cinco e iOS seis aserciones históricas de simulación; verificar paquete | No sustituye el plugin OCR | Pendiente | Pendiente |
| QR, cámara, micrófono, enlaces y selector | Cobertura parcial simulada | No dar por terminado el circuito interactivo | Permisos del servidor no acreditan cámara | Pendiente | Pendiente |
| Presupuestos, cobros y módulos de gestión | Cobertura automatizada | Cobertura parcial histórica | Módulos, evidencia alojada histórica | Pendiente | Pendiente |
| Cierre, concurrencia y recuperación | Cobertura automatizada | Persistencia entre procesos Windows/iOS histórica | Recuperación y peticiones HTTP superpuestas históricas | Pendiente | Pendiente |
| Nueva cola de ensayos y XML conservado | Pruebas preparadas; consultar ejecución actual | Pendiente en la nueva interfaz | Registro y copia formato 14 históricos | Pendiente | Pendiente |
| Aceptación fiscal oficial | No acreditada | No acreditada | No se llamó al servicio fiscal | No acreditada | No acreditada |

Referencias verificables: `evidence/native-ios-validation.json`, `evidence/windows-native-validation.json`, `evidence/build26-ios-simulator.log.txt`, `evidence/fiscal14-hosted-summary.json` y `evidence/fiscal-confirmed-xml-xsd.json`. Las rutas se interpretan desde la raíz de TallerFlow. El archivo `native-ocr-latest-status.json` conserva un fallo anterior; el registro posterior build26 documenta su corrección en simulador, no uso físico.

## 2. Inventario observado y límites del acceso

Inventario de lectura realizado entre las 15:41 y las 15:45 UTC del 7 de octubre de 2026; véase `evidence/native-pilot-inventory-20261007.json`.

| Elemento | Hecho observado | Límite de esta comprobación |
| --- | --- | --- |
| Android | SDK en `/Users/benja/Library/Android/sdk`; ADB 37.0.1; un servidor ADB ya escucha en el puerto 5037. La consulta posterior del agente principal devolvió una lista vacía | La primera consulta del subagente estaba bloqueada por red; la posterior no muestra dispositivos ADB reconocidos en ese momento, sin afirmar que no puedan conectarse después |
| iOS | Herramientas `devicectl` de Xcode disponibles; el agente principal repitió la consulta y también agotó cinco segundos, con diagnóstico DVTFilePathFSEvents | CoreSimulator no pudo acceder a su servicio/registro. El agotamiento de espera no permite afirmar que falten el iPhone o los simuladores |
| Windows | VirtualBox 7.2.20 instalado; el registro local consultado contiene cero máquinas registradas. Después, el usuario confirmó que no tiene Windows | No se inició ninguna máquina. Falta un entorno Windows con licencia y acceso para el ensayo manual |
| Teléfono del usuario | El usuario indicó un «iPhone 17 e» | Modelo y conexión física no confirmados mediante este inventario |

La comprobación no instaló herramientas, no aceptó licencias, no inició máquinas ni solicitó permisos nuevos. Las licencias Android ya fueron aceptadas según la respuesta del usuario; no deben volver a solicitarse. Un bloqueo de la herramienta de inventario no se registra como fallo de TallerFlow.

## 3. Preparar cuentas y datos ficticios

Crear un identificador breve de ejecución, por ejemplo `PILOTO0710A`, y cambiarlo al repetir para distinguir datos. La cuenta administradora personal confirmada es `ramirezbroja013@gmail.com`. Su titular inicia sesión personalmente en la aplicación y escribe allí la contraseña. Nunca se solicita ni se registra en el chat.

Desde **Configuración y puesta en marcha → Cuentas y permisos**, preparar oficina, operario A y operario B. Usar cuentas ficticias exclusivas del ensayo, por ejemplo `oficina.piloto0710a@example.invalid`, `operario.a.piloto0710a@example.invalid` y `operario.b.piloto0710a@example.invalid`. El alta no envía correo. Introducir contraseñas nuevas y distintas en la aplicación, mínimo doce caracteres; no escribirlas en este documento. Si Auth rechaza un dominio reservado, registrar el rechazo y usar un alias de pruebas bajo control del titular, sin enviar mensajes ni reutilizar otra identidad.

No desactivar al único administrador. Registrar el identificador de cada cuenta, miembro y dispositivo ficticio, sin sus credenciales. Para concurrencia real hacen falta sesiones independientes; cambiar el perfil de la demo o alternar cuentas en un único teléfono no sustituye ese ensayo.

Guardar estos CSV como UTF-8 en una carpeta de pruebas a la que el selector dé acceso. Usan `;`, sin datos personales ni números de teléfono. Cambiar los códigos para cada ejecución. Importar clientes antes que vehículos.

**clientes.csv**

```csv
codigo;nombre;telefono;email;nif;direccion
PILOTO0710A;Cliente ficticio PILOTO0710A;;;;
PILOTO0710B;Segundo cliente ficticio PILOTO0710A;;;;
```

**vehiculos.csv**

```csv
matricula;pais;vin;vehiculo;motor;km;codigo_cliente
TST0710A;ES;;Vehículo ficticio A;Motor ficticio;100000;PILOTO0710A
TST0710B;ES;;Vehículo ficticio B;Motor ficticio;25000;PILOTO0710B
```

**catalogo.csv**

```csv
referencia;descripcion;unidad;precio;coste;iva_porcentaje;existencias;stock_minimo;proveedor
PILOTO0710ACEITE;Consumible ficticio;ud;10.00;6.00;21;10;2;Proveedor ficticio
```

El ejemplo de NIF y las matrículas posteriores son muestras de ensayo, no identidades de clientes. Fotografiar una hoja con texto inventado o una pieza sin datos personales. No fotografiar DNI, tarjetas, pantallas con sesiones ni matrículas reales.

## 4. Instalar y comprobar la revisión

### Windows

Extraer completamente el ZIP vigente. Para el recorrido de instalación ejecutar `installer/TallerFlow-Setup.exe`; registrar destino, versión y apertura posterior. Si se usa la alternativa portable, conservar juntos todos sus archivos y registrar que no se ha probado el instalador. Probar desde una cuenta Windows normal, cerrar la aplicación, abrirla de nuevo y comprobar la persistencia. No aceptar costes, adquirir una licencia ni instalar una máquina de pago para este ensayo.

### Android

Extraer `deliverables/TallerFlow-piloto.apk` del paquete vigente e instalarlo en el dispositivo o emulador de pruebas identificado. Es un APK de piloto, no una publicación de Google Play. Registrar si se autoriza la instalación desde ese medio, la versión Android, espacio disponible y apertura. En emulador, comprobar previamente espacio de la partición y arranque completo: un APK compilado con emulador que no arranca no es una prueba OCR ejecutada. No conceder cámara o micrófono hasta su recorrido; probar también denegación y cancelación.

### iOS

El TAR `TallerFlow-iOS-simulador.tar.gz` conserva `Runner.app`, enlaces y permisos. Extraerlo e instalarlo en un simulador compatible de Xcode; registrar versión, arquitectura y revisión. Ese archivo no se instala en el iPhone.

Para el iPhone, conectar el teléfono, desbloquearlo, confiar en el Mac y completar personalmente los avisos del sistema, incluido modo de desarrollador cuando sea necesario. Abrir `ios/Runner.xcworkspace`, seleccionar el teléfono y el equipo personal Apple ya configurado, y generar la aplicación de desarrollo desde la misma revisión. La configuración pública del piloto es `config/pilot.public.json`. Si se utiliza el envoltorio de Flutter del proyecto, ejecutar desde TallerFlow `../../work/flutterw devices` y `../../work/flutterw run -d IDENTIFICADOR --dart-define-from-file=config/pilot.public.json`.

Registrar firma y arranque, duración/limitaciones del perfil de desarrollo que muestre Xcode y cualquier aviso pendiente. No se da por preparado TestFlight, distribución de App Store ni un IPA instalable mediante el paquete de simulador. No contratar membresías para completar este protocolo.

## 5. Recorridos reproducibles

En cada caso, anotar los pasos efectivamente ejecutados, resultado, revisión y evidencia. Si falta un equipo o acceso, marcar **Pendiente: dependencia concreta**, conservando los avances de otras plataformas.

### P01. Inicio de sesión y permisos efectivos

1. Abrir la entrega vigente y usar **Entrar al taller** con la cuenta personal, introduciendo la contraseña en el dispositivo. Comprobar nombre del taller, perfil y conexión real; no confundir un perfil de demo con Auth.
2. Crear oficina y dos operarios ficticios desde administración, con motivo. Verificar que un alta repetida incierta conserva la misma solicitud y no modifica una contraseña ya creada.
3. Abrir una sesión independiente por perfil. Operario A ve su trabajo asignado; B no accede a órdenes de A sin asignación. Oficina consulta precios; costes requieren el permiso aplicable. Administración puede gestionar ajustes. Probar las negativas desde la interfaz y el acceso enlazado.
4. Retirar acceso adicional de un operario, desactivar un miembro ficticio y volver a consultar desde su sesión abierta. Verificar que el servidor niega nuevas operaciones y que la interfaz no mantiene información restringida como una autorización vigente. Reactivar solo para continuar el ensayo y con motivo.
5. Cerrar sesión y reiniciar. Comprobar que la aplicación exige acceso según su política; no atribuir una sesión recuperada al acceso sin contraseña de otro usuario. Con pendientes, comprobar los avisos antes de cerrar y no borrar los datos para eludirlos.

### P02. Configuración, precios y motivos

1. Como administrador, preparar tarifas, impuesto de ensayo, catálogo y plantilla antes de crear la orden. Anotar valores originales. Cambiar un ajuste con motivo y revisar auditoría.
2. Crear una orden, añadir consumible y tiempo autorizado. Cambiar después la tarifa: la orden y el documento anterior conservan sus importes; una orden nueva usa la configuración nueva.
3. Revisar precio con motivo, aplicar descuento y añadir consumo sin cobro justificado. Comprobar base, cuota, total y coste/margen estimado frente a un cálculo independiente. Operario sin permiso no puede consultar el coste ni cambiar el precio.
4. Probar cantidad, descuento o tipo inválidos. Debe existir una validación clara sin modificar el original. No convertir estos documentos de trabajo en facturas.

### P03. CSV y selector nativo

1. Abrir **Importar datos del taller → Guardar plantilla CSV**. Elegir carpeta, guardar y abrir externamente el archivo; comprobar UTF-8 y cabecera. Repetir cancelando: no queda una importación ni un archivo confirmado.
2. Usar **Seleccionar CSV y revisar**: clientes, vehículos y catálogo ficticios, en ese orden. Revisar antes de confirmar; comprobar relaciones y cantidades resultantes. Catálogo requiere administrador; clientes/vehículos, oficina o administrador.
3. Importar de nuevo el mismo CSV: la revisión detecta duplicados y no sobreescribe silenciosamente. Probar una fila sin columna obligatoria y un vehículo con cliente inexistente. Conservar original y errores por fila.
4. Probar fichero que supere 500 filas o 1 MiB, y denegar acceso al archivo. Registrar el rechazo sin copiar contenido sensible ni abrir rutas privadas ajenas. Un selector simulado en tests no acredita este recorrido nativo.

### P04. Recepción, tareas y varios operarios

1. Oficina crea **Nueva recepción** para `TST0710A`, describe un síntoma ficticio y asigna dos tareas a A y B. Cambiar prioridad, responsable y un bloqueo con motivo.
2. Cada operario abre su sesión y comienza/pausa/reanuda su tarea. Comprobar tiempos, consumos y prohibición de sesiones activas duplicadas. Una tarea bloqueada explica el impedimento y no avanza sin resolverlo.
3. Oficina consulta el estado conjunto. Reasignar mientras un operario tiene una edición pendiente: registrar el conflicto o rechazo, conservar el pendiente y evitar una reasignación silenciosa de autor.

### P05. Fotografías, orientación y privacidad

1. En una orden autorizada abrir **Fotografías**. Capturar una hoja ficticia en vertical y horizontal; probar cámara trasera/frontal cuando estén disponibles. Comprobar orientación visible y pie de foto. Cancelar una captura no cambia el original.
2. Elegir una foto ficticia del selector. Probar permiso denegado y archivo ausente. En iOS, el archivo temporal privado permitido debe aceptarse; una ruta exterior al ámbito autorizado debe rechazarse. No ampliar el permiso a toda la carpeta de usuario para superar el caso.
3. Cortar la conexión real, capturar otra foto, cerrar y reabrir. Debe recuperarse como pendiente local cifrado y poder sincronizarse sin duplicar el original. Comparar su identificador y huella cuando la evidencia autorizada los muestre.
4. Desde un perfil no autorizado y otra cuenta/taller ficticio, intentar acceder a la foto. No debe existir un enlace público permanente. Retirar el permiso en una segunda sesión y repetir la consulta; el servicio de fotos debe reevaluar el acceso.
5. Si una foto llega después del cierre o de la recuperación, usar **Incorporar tras revisión** o **Archivar con motivo**. No desaparecerá por repetir la sincronización. Registrar el motivo y su rastro.

### P06. OCR y dictado con revisión humana

1. Leer por cámara o imagen una hoja con `P0301`, `REF-PILOTO` y una matrícula ficticia. Repetir con giro/EXIF, imagen en blanco y archivo ausente. Comprobar que no se inventan observaciones.
2. Revisar el borrador, editar una alternativa y cancelar: el campo original permanece. Confirmar una elección: únicamente cambia el campo revisado. Repetir lectura sin sustituir datos confirmados automáticamente.
3. Denegar permiso de cámara/micrófono. La recepción manual sigue disponible. Para dictado, hablar un texto ficticio y comprobar revisión, cancelación y ausencia de subida a un modelo de IA real. Si el sistema necesita un servicio o paquete no disponible sin coste, registrar exactamente esa dependencia y mantener la entrada manual.
4. Marcar cámara y micrófono físicos solo si se usaron realmente. Un JPEG de prueba en emulador o Apple Vision en simulador acredita OCR nativo de imagen, no una cámara física.

### P07. QR y enlaces de la orden

1. Mostrar **QR de la orden** y **Copiar código** en la sesión de oficina. Desde una segunda sesión autorizada usar **Abrir orden por QR o código** y, donde exista cámara, **Escanear QR de la orden**.
2. Abrir el enlace `tallerflow://order/UUID` con la aplicación cerrada y abierta; comprobar la orden y sus permisos. Probar un QR de otra aplicación, un UUID inexistente y una orden sin asignación. No se abre información no autorizada.
3. Denegar permiso o cancelar lectura. Debe poder escribirse/pegarse **Código o enlace**. En Windows, probar entrada de código o lector disponible; no afirmar cámara validada si no se dispone de ella.

### P08. Presupuestos y autorización versionada

1. Crear inspección y presupuesto desde oficina; guardar su versión, importes, partidas y notas. Debe indicar **Presupuesto · no es una factura**.
2. Revisarlo y crear una versión nueva. El original sigue disponible e inmutable. Autorizar una versión concreta y comprobar que una autorización antigua no aprueba la nueva.
3. Preparar un enlace/código del portal para esa versión y sus fotos permitidas. Probar caducidad, código incorrecto y documento de otra orden. No enviar el enlace a una persona ni guardar su código vigente en evidencia pública.
4. El portal está publicado en **https://tallerflow.pages.dev/**, desde `portal-client` y limitado al repositorio `tallerflow` autorizado. Se comprobó la página y el rechazo sin secreto válido; falta este recorrido positivo con enlace/código legítimos y versión/fotos permitidas. Registrar la navegación final, caducidad y revocación. El servicio HTTP previo o la demo del portal no sustituyen esa prueba desde el sitio publicado; no volver a pedir el permiso ya concedido.

### P09. Cobros, devolución y documentos conservados

1. En **Cobros y saldo**, registrar **Cobro ya recibido** ficticio parcial y después el resto. Comparar saldo; reiniciar y comprobar que no se duplican. No realizar transferencias, tarjetas ni cobros reales: aquí se registra un movimiento manual.
2. Registrar **Devolución ya realizada** con motivo y referencia adecuada; probar exceso y negativa de un perfil sin permiso. Conservar el movimiento anterior y la auditoría.
3. Generar el documento de trabajo/PDF disponible, guardar mediante selector, cancelar otro guardado y abrir externamente. Comprobar versión, importes y texto de documento de trabajo. Cambiar precios o propietario y comprobar que el original no se regenera con los datos nuevos.

### P10. Sin conexión, reinicio y confirmación incierta

1. Con sesión legítima y datos previamente cargados, cortar Wi-Fi/red del dispositivo de pruebas. Anotar conexión efectiva; el botón de simulación de la demo no sirve para afirmar pérdida de red nativa real.
2. Crear tiempo, consumo, cambio de tarea y foto. Anotar identificadores visibles de los pendientes. Cerrar completamente y reabrir la aplicación; comprobar pendientes y datos conservados. No reinstalar ni limpiar el contenedor como sustituto del reinicio.
3. Restablecer conexión y sincronizar. Comprobar un único efecto, autor correcto y cola resuelta. Repetir sincronización y apertura: no cambia el documento confirmado ni aparecen duplicados.
4. Para confirmación incierta, registrar un caso en el que se pierde la respuesta después de que el servidor haya aceptado la misma solicitud. Si no puede reproducirse de forma controlada, marcar ese subcaso pendiente. El reintento conserva identificador y contenido; un error de transporte no permite suponer rechazo ni generar una segunda solicitud.

### P11. Concurrencia de oficina y dos operarios

1. Abrir tres sesiones independientes sobre la misma orden. Registrar equipos y cuál es físico, emulado o simulado. Obtener la misma versión inicial.
2. A y B añaden trabajo permitido; oficina revisa simultáneamente. Comprobar acumulación sin duplicados y autoría. Editar simultáneamente un dato exclusivo: debe producirse un conflicto visible, no la pérdida silenciosa de una edición.
3. Resolver con motivo, volver a cargar y comprobar el historial. Repetir el reintento del comando ya aceptado: conserva un efecto.
4. Distinguir peticiones HTTP superpuestas, varias sesiones nativas y transacciones simultáneas observadas del servidor. No atribuir IDs internos de procesos PostgreSQL si no se midieron.

### P12. Cierre coordinado, retirada y llegada tardía

1. Mantener un operario con un pendiente sin conexión. Oficina solicita cierre: no debe aprobarlo como si todos los dispositivos hubieran sincronizado.
2. Reconectar, sincronizar y obtener las confirmaciones correspondientes. Añadir otra edición antes del cierre definitivo: la revisión cambia e invalida una confirmación de una versión anterior.
3. Cerrar con **Sincronizado: bloquear y confirmar** cuando corresponda. Comprobar estado bloqueado y documento original. Intentar edición desde una sesión antigua: queda rechazada o conservada para revisión, sin cambiar el original.
4. Antes de retirar un dispositivo ficticio, guardar sus pendientes y una copia. Retirarlo con motivo desde administración y comprobar que la sesión antigua no puede seguir enviando. Una llegada tardía se conserva para revisión; no se borra para que el cierre parezca limpio.

### P13. Matrícula, propietario e historial protegido

1. Cambiar la matrícula ficticia y luego el propietario al segundo cliente ficticio, con motivos. Consultar el historial consolidado por vehículo; las tareas e información técnica permanecen.
2. Verificar que los documentos anteriores conservan la identidad que tenían al emitirse como documentos de trabajo. El nuevo propietario no obtiene documentos personales del anterior por consultar el historial técnico.
3. Probar búsqueda por matrícula anterior y acceso por una orden anterior. Registrar permisos y resultado; no compartir una copia antigua que contenga datos personales en un ensayo real.

### P14. Copia completa y recuperación aislada

1. En **Copias y recuperación**, elegir **Copiar servidor y este equipo**, incluyendo al menos una foto y un registro local pendientes, documentos confirmados y auditoría. Guardar todas las partes `.tfpart` y una frase privada de doce o más caracteres fuera del chat.
2. Reiniciar y verificar que todas las partes existen. Probar una parte ausente, frase incorrecta y contenido alterado en una copia duplicada del archivo: debe rechazarse sin sustituir el estado actual.
3. Restaurar únicamente en el proyecto de recuperación autorizado `qnbgbgumvxmmipjlkcgb`, con su contexto de ensayo aislado y la sesión administradora de destino requerida. El permiso específico del destino ya está concedido; no restaure sobre el taller de uso normal para probar este caso. Comprobar los requisitos de destino vacío/bootstrap antes de ejecutar.
4. Comparar registros, documentos, auditoría, fotos originales y pendientes de origen. Las credenciales/sesiones de origen no se convierten en sesiones del destino. Los pendientes de otro dispositivo no se reenvían como si pertenecieran al dispositivo nuevo.
5. Verificar instalaciones/series restauradas congeladas y sus cabeceras intactas. Crear una instalación de ensayo nueva para continuar; reintentar la restauración no debe congelar ni sobrescribir esa instalación nueva. Conservar el resultado de cada intento y la revisión del formato de copia.

### P15. Registro de ensayos, cola exacta y recuperación

1. Solo como administrador con sesión/dispositivo activos, abrir **Registro de ensayos → Actualizar registro**. Elegir un perfil de preparación compatible exclusivamente ficticio. Un perfil de ensayo no determina las obligaciones fiscales de un taller.
2. En **Preparar ensayo**, usar emisor `B12345678`, destinatario `12345678Z`, instalación `piloto-0710a-a`, prefijo `ENSAYO-PILOTO`, fecha actual y descripción ficticia. Añadir una partida: cantidad `1,500`, precio `33,33`, descuento `12,50 %`, operación sujeta IVA `21 %`. El cálculo esperado es base **43,75 €**, cuota **9,19 €** y total **52,94 €**. Revisar antes de confirmar.
3. Preparar otro caso sin conexión tras una lectura autorizada. Debe verse **Ensayo local · sin confirmación del servidor** e **Identificador conservado**. Anotar ese UUID; todavía no se atribuye un número confirmado del servidor. Reiniciar y comprobar el mismo identificador y contenido.
4. Recuperar conexión y usar **Reintentar misma solicitud**. Debe pasar a **Confirmado por el servidor** una sola vez, con secuencia, actor, dispositivo, fecha y huella originales. Si la respuesta fue incierta, consultar primero y reconciliar; no generar un UUID nuevo ni renumerar por un error de red.
5. Mientras haya un pendiente, conflicto o rechazo sin revisión en la misma cadena, no debe encadenarse otro ensayo ignorando el anterior. Probar conflicto de cabecera y **Registrar revisión** con motivo. La revisión conserva la solicitud original y no sustituye automáticamente su cabecera esperada para fingir que fue aceptada.
6. Como oficina/operario no aparece la administración de ensayos ni se exporta una copia que revele un registro fiscal almacenado restringido. Cambiar el rol o retirar permisos desde otra sesión y volver a consultar: un rechazo de acceso revoca la disponibilidad, sin borrar los pendientes conservados ni tratarlos como confirmados.
7. **Retirar ensayo SERIE-N** requiere motivo y agrega una entrada ligada al original. No borra el original ni representa una anulación fiscal ante Hacienda.
8. Repetir P14 con un ensayo confirmado y otro pendiente. La instalación restaurada queda congelada. Cambiar/restaurar el dispositivo conserva la identidad del dispositivo de origen en sus filas; el equipo nuevo no reenvía el pendiente con otra identidad. Reiniciar después de la sustitución y comprobar que esa restricción es durable. Continuar con instalación y serie nuevas de ensayo, sin reutilizar el número ni la cadena restaurada.

### P16. XML técnico guardado, huellas y copia

1. Abrir **XML técnicos de ensayo** y seleccionar un original confirmado. Un pendiente local no permite preparar XML como si estuviera confirmado. Introducir fabricante/sistema/versión ficticios y la identificación técnica requerida; conservar la instalación del registro.
2. Usar **Preparar XML**. Anotar identificador del original, fecha de generación, versión del generador, **Huella interna del registro**, **Huella AEAT del XML de ensayo** e **Integridad del archivo XML (SHA-256)**. Son valores distintos; ninguna huella acredita aceptación oficial.
3. Usar **Guardar XML de ensayo**, elegir destino, abrir el archivo y comprobar sus bytes contra SHA-256 conservado. Cancelar otro guardado no altera la copia técnica. Mantener la huella asociada a esos bytes exactos, no a una regeneración posterior del texto.
4. Reiniciar y volver a abrir **Copias técnicas conservadas**. Cambiar después el perfil/ajuste o versión local del generador en un entorno controlado: la copia existente conserva sus bytes, fecha, versión y huellas. La cadena no admite cambiar silenciosamente la identidad técnica para continuar.
5. Exportar/restaurar con P14 y comparar las copias XML. Las cabeceras restauradas permanecen congeladas; la nueva instalación inicia una cadena distinta y no recalcula el XML histórico.
6. Probar una combinación fiscal no soportada por la proyección técnica: debe rechazarse claramente, sin transformar el documento en una factura. La validación XSD local documentada compara con esquemas oficiales fijados; no llama a la AEAT ni constituye certificación o aceptación fiscal.

### P17. Compras, garantías, diagnóstico, biblioteca y planificación

1. Compras/almacén: preparar pedido ficticio, recepción parcial y final, unidades/conversión y devolución justificada. Comparar existencias y coste; repetir el mismo movimiento no lo duplica. Probar negativo o cantidad incompatible y permisos de operario.
2. Garantía: abrir un expediente sobre trabajo previo, enlazar la orden/documento original y registrar decisión con motivo. Un trabajo nuevo requiere su autorización; no modifica el documento cerrado ni finge aprobación del proveedor.
3. Cuaderno de diagnóstico: registrar síntoma, hipótesis, comprobación y resultado ficticios, con fotografía autorizada. Una recomendación no se convierte en procedimiento validado sin revisión.
4. Biblioteca: publicar y retirar un contenido interno validado; consultar desde los perfiles permitidos y verificar autor/versiones. No copiar documentación técnica comercial ni activar conectores sin licencia/proveedor acreditados. IA real continúa desactivada.
5. Agenda/mantenimiento/flotas: programar cita, detectar solapamiento, registrar mantenimiento por fecha/km y relacionar dos vehículos de una flota ficticia. Cambiar propietario/permiso y comprobar que no se exponen documentos de otro cliente. No enviar recordatorios ni mensajes durante el ensayo.

## 6. Hoja de ejecución y criterio de cierre

Crear una fila por recorrido, plataforma y revisión. Cuando un caso se repita tras una corrección, conservar la fila del fallo y añadir otra, sin reemplazar la evidencia anterior.

| Caso/subcaso | Revisión/paquete | Plataforma y equipo | Capa | Cuenta/perfil ficticio | Fecha UTC | Resultado | Evidencia/dependencia |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P01 | Por registrar | Por registrar | NativoSupabase | Por registrar | Por registrar | Pendiente | Inicio de sesión personal |
| P05 cámara | Por registrar | Por registrar | Dispositivo físico | Por registrar | Por registrar | Pendiente | Equipo conectado y permiso |
| P10 incierta | Por registrar | Por registrar | NativoSupabase | Por registrar | Por registrar | Pendiente | Reproducción controlada |
| P14 | Por registrar | Por registrar | NativoSupabase | Administrador | Por registrar | Pendiente | Destino aislado preparado |
| P15/P16 | Por registrar | Por registrar | NativoSupabase | Administrador | Por registrar | Pendiente | Paquete con pantallas nuevas |

Para cada resultado aprobado adjuntar estado previo, acción, resultado observado y comparación esperada. Un bloqueo del entorno se marca pendiente, no aprobado ni fallo de producto. Una captura aislada no sustituye comprobar persistencia después del reinicio. Para cerrar el piloto de una plataforma deben completarse los recorridos aplicables con su entrega vigente; un plugin/dispositivo no disponible se declara como limitación material.

## 7. Limpieza del ensayo y dependencias personales

Al terminar, exportar las evidencias sin secretos y conservar los originales/auditoría según la política del ensayo. Revocar enlaces y códigos de portal; desactivar miembros ficticios con motivo, retirar sus dispositivos y cerrar sus sesiones. No borrar ni desactivar la cuenta administradora personal. No eliminar documentos inmutables o fotos pendientes para aparentar una cola vacía. Los servicios temporales administrativos de pruebas solo deben existir con autorización concreta, retirarse después y dejar evidencia de revocación; este protocolo no crea uno nuevo.

Dependencias personales para los tramos pendientes: conectar/desbloquear/confiar el iPhone y completar avisos de firma; introducir personalmente la contraseña administradora en cada cliente pertinente; disponer de Windows con licencia y acceso para el instalador/manual, ya que el usuario confirmó que no tiene Windows; disponer de Android físico si se pretende validar su cámara/micrófono/QR. Cloudflare está autorizado y el portal publicado: continúa su recorrido positivo sin pedir otra vez ese acceso. Usar equipos/cuentas existentes no requiere contratar un servicio; cualquier coste, membresía, cuota o descarga de pago necesita otra decisión previa. No se vuelve a pedir aceptación Android ni permiso del Supabase de recuperación ni acceso específico Cloudflare ya concedidos.

IA permanece apagada por decisión expresa: no se solicitan créditos ni claves para este piloto. Los adaptadores técnicos requieren proveedor, contrato/licencia y equipo de diagnosis de cada cliente antes de acreditar integración. La facturación fiscal completa sigue teniendo trabajo de implementación y pruebas oficiales: los ensayos, XSD y huellas de este protocolo no la declaran terminada.
