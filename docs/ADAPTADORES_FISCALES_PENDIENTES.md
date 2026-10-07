# Adaptadores fiscales · catálogo de trabajo

Consulta oficial del 7 de octubre de 2026. La elección de un territorio en preparación no activa un adaptador ni determina obligaciones. Los importes y documentos existentes permanecen intactos.

| Circuito | Material oficial localizado | Implementación / validación actual |
|---|---|---|
| AEAT SIF / VERI*FACTU | XSD, huella, QR, validaciones y servicios en el [índice técnico](https://www3.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/informacion-tecnica/especificaciones-tecnicas-firma-electronica-registros-evento.html) | Cálculo, huellas y borradores técnicos F1/anulación locales; sin transporte ni aceptación oficial. No soporta todavía emisión, serie concurrente o rectificación completa |
| SII estatal | [Información técnica AEAT](https://sede.agenciatributaria.gob.es/Sede/iva/suministro-inmediato-informacion/informacion-tecnica.html): portal, WSDL, esquemas y descripción | Adaptador de libros, estados/respuestas y reintentos pendiente; no sustituirlo por un registro SIF |
| Álava | [Documentación de Hacienda](https://web.araba.eus/es/hacienda/ticketbai/documentacion-tecnica): esquemas de envío/anulación y avisos TLS | Implementación, firma, cadena, identificación/QR y pruebas específicas pendientes |
| Bizkaia | [BATUZ, documentación técnica](https://www.batuz.eus/es/documentacion-tecnica): TicketBAI, LROE, estructuras, versiones, validaciones y pruebas | Adaptadores separados de registro TicketBAI y envío LROE pendientes. Contemplar libros por sujeto/capítulo y estados propios |
| Gipuzkoa | Marco propio identificado en [TicketBAI del Gobierno Vasco](https://www.euskadi.eus/ticketbai/) | Localizar y fijar las especificaciones concretas vigentes antes de implementar; no reutilizar sin revisión el transporte de otra Hacienda |
| Navarra | Revisión de su administración y circuitos concretos | No asignar TicketBAI por analogía. Selección/implementación/validación específicas pendientes |
| B2B electrónico y Administraciones | Normativa citada en FACTURACION_ESPANA_PENDIENTE.md | UBL/EN 16931, formatos públicos, entrega y estados pendientes; separar de las huellas SIF |

## Hallazgos que afectan al diseño

Bizkaia publica LROE 1.0.10 y documentación de pruebas 1.0.9, fechadas el 12 de agosto de 2026, además de estructuras actualizadas en septiembre. El adaptador deberá fijar versiones verificadas; los formatos de otras haciendas no constituyen prueba de compatibilidad. El índice también ofrece certificados públicos para el **entorno de pruebas** del LROE. Se investigará su uso conforme a las instrucciones oficiales cuando el adaptador esté construido; no se afirma que todos los ensayos requieran un certificado personal. No se han descargado ni utilizado certificados en esta ejecución.

La documentación oficial de [SII](https://sede.agenciatributaria.gob.es/static_files/Sede/Procedimiento_ayuda/G417/FicherosSuministros/V_1_1/SII-Descripcion-ServicioWeb-v1-1_es_es.pdf) exige autenticación de cliente con certificado admitido. Antes de conectar transporte se verificará el entorno, la identidad permitida, representación y certificado aplicables. La investigación y las pruebas locales no requieren contratar un servicio.

## Condiciones de implementación

- Contrato común de cálculo/documento inmutable y respuestas, con transporte específico por circuito. Nunca remitir un documento a otro destino como reintento automático.
- Numeración y cadena aisladas por taller/emisor/instalación; recibir un resultado incierto exige reconciliar antes de duplicar. Mantener originales y respuestas íntegros.
- Recargos, retenciones, regímenes especiales, clientes no residentes y rectificativas se implementarán explícitamente. Las opciones del perfil sirven para preparar, no para suplir esas reglas.
- Solo pruebas ficticias y recursos gratuitos. Los certificados/credenciales reales se conectarán por un medio seguro autorizado, sin chat, cliente Flutter ni ZIP. Cualquier coste requiere consulta previa.

Este catálogo conserva tareas de desarrollo independientes. No constituye una lista de adaptadores disponibles ni una declaración de cumplimiento fiscal.
