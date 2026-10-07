# XML desde registros confirmados · documento de trabajo

Corte: 7 de octubre de 2026, 18:02, España peninsular. Proyección técnica local y circuito de aplicación integrados en la fuente, **sin emisión, transmisión, firma ni aceptación oficial**. Publicación/compilación y recorrido nativo de la revisión nueva pendientes. No transforma notas, PDF o series `ENSAYO-…` en facturas.

## Correspondencia e inmutabilidad

`FiscalDraftXmlChain.generateGeneralRegime` recibe la cadena completa confirmada por el servidor, de un taller, emisor e instalación, junto con preparación, emisor y sistema técnico explícitos. Rechaza saltos, duplicados, cambios de identidad, series incoherentes, huellas internas alteradas y retiradas que no corresponden al original. No usa tarifas ni impuestos actuales para recalcular el documento.

El artefacto conserva el registro fuente completo, emisor, fabricante, sistema, versión, instalación, preparación, zona del calendario y versión del generador `tallerflow-sandbox-f1-1`. Sus cuatro identidades tienen funciones diferentes:

| Campo | Función |
|---|---|
| `ledgerHash` | Huella interna original del servidor, con dominio `TALLERFLOW-DRAFT-1`; no es la huella AEAT. |
| `inputHash` | Identidad del snapshot técnico completo, con dominio `TALLERFLOW-XML-SNAPSHOT-1`. |
| `aeatHash` | Huella calculada con los campos y orden del adaptador AEAT. |
| `xmlSha256` | Integridad de los bytes UTF-8 del XML conservado. |

Las altas se encadenan por emisor e instalación, incluso cuando cambian de serie. Las retiradas administrativas permanecen en la cadena interna y en los metadatos; **no generan registros XML de anulación**. Un borrador retirado conserva su XML original. La cadena técnica de altas conserva la huella de la alta anterior; nunca utiliza en ese lugar la huella interna de una retirada.

`validateFiscalDraftXmlStoredArtifact` verifica bytes, snapshot y correspondencia con el registro confirmado. Reproduce la proyección con el generador guardado para compararla, sin sustituir los bytes originales. Permite que la recuperación cambie el contexto `workshop_id`, conservando el cuerpo y la identidad original. El controlador conserva artefactos anteriores por registro/versión/snapshot y no los reemplaza al cambiar los ajustes. Una versión de generador no reconocida se rechaza, no se actualiza silenciosamente.

Las huellas comprueban integridad y correspondencia; no firman al emisor ni prueban el origen de datos por sí solas. La consulta fuente debe proceder del servicio autenticado y autorizado. Los permisos, cifrado y almacenamiento pertenecen al flujo de la aplicación.

## Circuito de aplicación, almacenamiento y copia

Desde **Configuración y puesta en marcha → XML técnicos de ensayo**, un administrador con acceso vigente selecciona un original confirmado obtenido de la vista autorizada del servidor. Un pendiente local o la demo no se presentan como documento confirmado que pueda proyectarse.

**Preparar XML** exige identificación técnica ficticia explícita: emisor, fabricante/NIF, nombre/identificador/versión del sistema, instalación y capacidades declaradas del ensayo. Al empezar una cadena se conserva también preparación y zona de contraste. Para extenderla se exige la misma identificación guardada; el perfil actual no modifica retroactivamente la preparación, el emisor ni el sistema.

`generateFiscalDraftXml` obtiene los originales de esa cadena, comprueba correspondencia y conserva los artefactos juntos mediante la escritura cifrada del almacén. Si ya hay XML para el registro, valida y devuelve el original conservado. Si falla la persistencia, revierte la lista en memoria; no confirma un guardado que no terminó. Reabrir valida artefactos, originales y predecesores, sin sobrescribir los bytes para reparar una incoherencia.

**Copias técnicas conservadas** muestra registro, instante, versión del generador, huella interna, huella técnica AEAT e integridad SHA-256. **Guardar XML de ensayo** utiliza el selector y exporta esos bytes UTF-8 exactos; cancelar no cambia el original. El `.xml` exportado es un archivo normal en el destino elegido, no una copia cifrada. El original dentro del almacén local sí está cifrado con AES-GCM y clave del almacenamiento seguro del sistema.

La copia portable incluye `fiscalDraftXmlArtifacts` con snapshots y bytes, además del registro local y cola. Se validan nuevamente durante recuperación, incluida correspondencia con el registro conservado; los predecesores no pueden faltar ni cambiar. Sustituir el dispositivo conserva los originales y no reenvía solicitudes de otro dispositivo con identidad nueva. Las instalaciones recuperadas permanecen congeladas y una instalación nueva inicia otra cadena de ensayo.

**Esta persistencia XML es local y viaja en la copia de la aplicación; no existe aún almacenamiento compartido de estos artefactos en Supabase.** La copia de servidor formato 14 conserva el registro de ensayo, cabeceras, series, recibos y auditoría, pero no sustituye la copia local de los XML generados. Sin esa copia, consultar el servidor desde otro dispositivo no recupera por sí solo los bytes XML guardados en el primero. Persistencia/autorización compartida y validación desde clientes reales siguen pendientes.

## Cálculos y tiempo

`FiscalCalculation.fromConfirmedSandbox` comprueba la política aritmética del servidor formato 1: una sola operación racional para precio, cantidad y descuento, redondeo de la base por partida, después cuota por partida. Mantiene las cantidades guardadas. Esta política puede diferir en un céntimo de la calculadora genérica que redondea el bruto y el descuento por separado; no cambia retrospectivamente los originales para hacerlos coincidir.

El `createdAt` completo del servidor se conserva. El XML usa el mismo instante normalizado a UTC y segundos, con `+00:00`, y admite registros ordenados en el mismo segundo. La secuencia y la precisión original sostienen el orden de la cadena interna. El calendario de contraste se guarda explícitamente, `Europe/Madrid` por defecto o `Atlantic/Canary`, utilizando los cambios de horario de la biblioteca ya incorporada. No depende de la zona del Mac.

La huella interna se vuelve a comprobar con el formato `jsonb::text` usado por PostgreSQL: claves ordenadas por longitud de bytes UTF-8 y después sus bytes, con espacios de separación conservados. Solo se admiten los tipos enteros del formato de ensayo; se rechazan coma flotante, Unicode inválido y enteros que perderían precisión en web.

## Circuito implementado y límites

La proyección actual es **F1 nacional, régimen general, calificación S1**, con partidas sujetas de IVA, IGIC o IPSI. El registro formato 1 no conserva datos de rectificación, identificación extranjera o clasificación/regímenes especiales. Esos casos se rechazan y requieren ampliar primero el contrato persistente. No se infiere una exención por su descripción ni se elige una obligación fiscal con el perfil.

Se comprueban localmente identidad de emisor, desglose completo, totales guardados, hasta doce grupos, fechas y tipos IVA del subconjunto general. Se rechazan macrodatos y descripciones de operación que exceden los 500 caracteres del XML. La regla de fecha usa el instante fuente y la zona guardada; no sustituye el reloj ni las comprobaciones censales del servicio oficial. La emisión y la transmisión permanecen desactivadas.

Se corrigió también el generador técnico anterior: para S2 escribe explícitamente tipo y cuota cero. Esto no habilita S2 en la proyección del registro formato 1 ni completa sus demás requisitos.

El dominio `fiscal_document_rules.dart` prepara localmente identidades alternativas, formas de documento y reglas de rectificaciones/subsanación, anticipos, recargos y retenciones; veinte pruebas están incluidas en la última batería global de 329. No añade sus campos al registro persistente ni habilita una pantalla o proyección XML de esos nuevos tipos. Hay correcciones adicionales de fecha, rechazo previo y desglose en revisión; su cobertura debe repetirse antes de acreditarlas.

Pendientes: integrar clasificación/régimen y nuevos campos SQL/interfaz; F2/F3/rectificativas y proyecciones completas de los casos nuevos; almacenamiento XML compartido; continuidad fiscal real, validaciones oficiales restantes, identificación/certificados, transportes y respuestas. Pasar XSD no acredita aceptación oficial ni cumplimiento fiscal completo.

## Verificación reproducible

- `tool/fiscal_draft_integrity_test.mjs`: tres vectores independientes obtenidos en PostgreSQL/PGlite, con claves Unicode, escapes y un cuerpo ficticio completo. Sin Auth alojado ni conexiones externas.
- `test/fiscal_draft_xml_test.dart`: correspondencia, cálculos conservados, cadena, retiro, series, copias de artefactos, alteraciones, permisos de circuito, datos no soportados y calendario español.
- `test/fiscal_draft_controller_test.dart`, `test/fiscal_queue_security_test.dart` y `test/fiscal_draft_xml_widget_test.dart`: circuito de cola/controlador/pantallas, almacenamiento/reinicio, permisos y conservación de XML con dependencias simuladas. No prueban Supabase desde una aplicación instalada.
- `test/verifactu_draft_test.dart`: vectores oficiales y generador anterior, incluyendo S2 y registros en el mismo segundo.
- `tool/generate_fiscal_xml_fixtures.dart`: integración local por VM, que produce dos XML desde registros ficticios y verifica originales y recuperación de bytes sin red.
- `tool/validate_fiscal_xml.py`: valida esos XML contra los XSD oficiales conservados y verifica que los bytes coinciden con el manifiesto. Resolución de esquemas sin red.

La integración VM tiene 13 comprobaciones; los vectores PostgreSQL son tres; el validador XSD llega a diez comprobaciones al incorporar los dos XML de registros confirmados a las ocho existentes. Última batería global local cerrada: 329 Flutter y analizador limpio; web release aprobada. Las pruebas específicas están incluidas en esa batería, no se suman como casos independientes. Las correcciones posteriores necesitan su nueva ejecución. Estas evidencias no son uso de un móvil físico, selector real, Auth alojado desde la pantalla ni aceptación de AEAT. La compilación anterior 6be045d no contiene el circuito nuevo.

## Fuentes oficiales contrastadas

- [AEAT, validaciones y errores, versión 1.2.2](https://www.agenciatributaria.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/Validaciones_Errores_Veri-Factu.pdf): reglas parciales de fechas, destinatarios, tipos, desglose y campos condicionados.
- [AEAT, huella SHA-256, versión 0.1.2](https://www.agenciatributaria.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/Veri-Factu_especificaciones_huella_hash_registros.pdf): campos, orden, codificación y ejemplos.
- [AEAT, esquemas del servicio](https://www.agenciatributaria.es/AEAT.desarrolladores/Desarrolladores/_menu_/Documentacion/Sistemas_Informaticos_de_Facturacion_y_Sistemas_VERI_FACTU/Esquemas_de_los_servicios_web/Esquemas_de_los_servicios_web.html): XSD fijados en `tool/fixtures/aeat/sources.json`.
- [AEAT, descripción de servicios, versión 1.0.3](https://www3.agenciatributaria.gob.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/Veri-Factu_Descripcion_SWeb.pdf): separación entre validación estructural y de negocio, y correspondencia de altas/operaciones.

Consulta pública del 7 de octubre de 2026; no se ha llamado a los servicios de remisión ni consulta fiscal.
