# Asistente revisable de TallerFlow

La pantalla de una orden ofrece consulta técnica y borrador para oficina. Primero muestra las fuentes originales y permite seleccionar las necesarias. La consulta técnica exige comprobar marca, modelo, año y motor; hay que revisar la variante cuando corresponda. Las fuentes y la pregunta no deben contener datos personales. La confirmación empieza sin marcar.

El servidor comprueba cuenta, taller, dispositivo, asignación, perfil y revisión de la orden. Usa el cuaderno vigente y casos validados; oficina puede incluir trabajos realmente registrados. Un DTC o un caso parecido no confirma una avería. La documentación técnica contratada todavía no está conectada: no se generan especificaciones numéricas ni instrucciones que requieran esos originales.

La respuesta es un borrador con fuentes. Para utilizar texto hay que revisarlo y confirmar personalmente. Se guarda la revisión y se puede copiar el texto; no se añaden trabajos, cargos ni modificaciones a documentos automáticamente. Una revisión/finalización/archivo solo cambia su estado si el guardado cifrado termina correctamente.

Cada consulta queda guardada antes de enviarse. Si se pierde la respuesta, «Recuperar respuesta» consulta el recibo original; no vuelve a pedir generación. El servidor conserva la reserva ante un resultado incierto. Archivar exige motivo y conserva consulta, fuentes y estado previo. Las copias locales incluyen estos registros. En un dispositivo diferente hay que conservar la evidencia del anterior; no se suplanta su sesión.

## Activación pendiente

La función workshop-ai está instalada en el principal y desactivada por defecto. No se han hecho solicitudes a OpenAI. Para activarla hacen falta créditos gratuitos de API confirmados, clave conectada mediante secretos del servidor y modelo/tarifas/límites aprobados. No enviar la clave al chat ni incluirla en Flutter, GitHub o copias. Una suscripción al producto de chat no acredita saldo de API.

Variables del servidor: TALLERFLOW_AI_ENABLED, TALLERFLOW_AI_FREE_CREDITS_CONFIRMED, TALLERFLOW_AI_MODEL, TALLERFLOW_AI_DAILY_MICRO_USD, TALLERFLOW_AI_REQUEST_LIMIT, TALLERFLOW_AI_MAX_OUTPUT_TOKENS, TALLERFLOW_AI_INPUT_RATE y TALLERFLOW_AI_OUTPUT_RATE. Las tarifas se expresan en microdólares por millón de tokens; presupuesto diario en microdólares. Los límites se reservan antes de consultar y se calculan con enteros. OPENAI_API_KEY solo existe en el servidor. Mantener generación desactivada hasta confirmar gratuidad, tarifas y ausencia de consumo de pago.

La integración utiliza Responses, salida estructurada y store:false. Esto no acredita por sí solo ausencia de toda retención del proveedor. La revisión humana y el acceso a originales autorizados siguen siendo necesarios. Documentación del proveedor: https://developers.openai.com/api/reference/resources/responses y https://developers.openai.com/api/docs/guides/structured-outputs.

La validación actual usa PostgreSQL/PGlite, Auth y proveedor simulados, más invariantes SQL alojadas con cambios revertidos. La generación real, sus resultados y los documentos técnicos quedan pendientes.
