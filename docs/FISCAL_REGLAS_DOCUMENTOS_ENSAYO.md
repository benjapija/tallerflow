# Reglas documentales de ensayo — documento de trabajo

Fecha de revisión: 7 de octubre de 2026. Estado: módulo puro local. No es una declaración de conformidad fiscal ni un adaptador aceptado por la AEAT.

## Alcance y separación

`lib/domain/fiscal_document_rules.dart` prepara y valida datos ficticios para futuros formatos documentales. Sus objetos mantienen `emissionEnabled`, `transmissionEnabled`, `persistenceImplemented` y `officialValidationImplemented` en `false`. Solo admite nuevas identidades con serie `ENSAYO-…`.

Este bloque **no cambia** el formato persistente `fiscal_draft_ledger` 1, sus migraciones, el controlador, las pantallas, los PDF, el transporte ni el XML actual de altas F1. El XML confirmado existente conserva su generador y su correspondencia con el registro inmutable. No se presentan estas reglas nuevas como si ya estuviesen disponibles en la aplicación o en Supabase.

El país y la identificación del cliente sirven para validar datos; no deciden por sí solos un impuesto, una exención ni un régimen obligatorio. El emisor nacional, el régimen general de IVA o el recargo declarado, las fechas, los tipos, las bases de retención y la causa de rectificación se aportan explícitamente. No se consulta el censo ni VIES.

## Reglas implementadas localmente

| Caso | Comportamiento del modelo | Restricción conservada |
| --- | --- | --- |
| Completa | Identidad, domicilio, partidas y destinatario explícitos; tipo técnico F1. | Solo IVA sujeto con tipos y fechas soportados. La excepción de completa sin destinatario no se implementa. |
| Simplificada | F2 sin destinatario; umbral de 400 €, impuesto incluido. | No aplica automáticamente el umbral de 3.000 € a reparaciones. |
| Comercio minorista declarado | Límite de 3.000 € para bienes de consumo final. | Rechaza uso empresarial, bienes principalmente profesionales y exclusiones declaradas. |
| Simplificada cualificada | Identifica al destinatario y conserva la petición; tipo técnico F1. | Debe cumplir también la regla de simplificación. Rectificar una cualificada sigue pendiente. |
| Rectificación | Nuevo registro y serie separados, referencia original, causa declarada y método I o S. | Solo causa declarada «resto» R4, o R5 para original F2; no deduce la causa del texto libre. |
| Subsanación del registro | Exige referencia y desglose conservado; mantiene identidad, fecha y estructura económica. Distingue rechazo inicial, rechazo de subsanación y recepción con errores. | No permite convertir un cambio económico en una subsanación ni resolver automáticamente respuestas oficiales. |
| Destinatario extranjero | `IDOtro` explícito, país y códigos 02–07 coherentes. | El formato no acredita identidad, censo, residencia ni tratamiento fiscal. |
| Anticipo declarado | Recibo, fecha recibida, operación futura e importe realmente recibido. | No soporta liquidación final/deducción de anticipos, recargos/retenciones simultáneos ni el supuesto intracomunitario exento. |
| Recargo y retención | Calcula enteros en céntimos con `BigInt`. | La aplicabilidad legal debe estar declarada; no asigna porcentajes por NIF, provincia o actividad. |

La base de completa/simplificada y la exigencia de serie diferenciada se investigaron en los artículos 4, 6, 7 y 15 del [RD 1619/2012 consolidado en BOE](https://www.boe.es/buscar/act.php?id=BOE-A-2012-14696). El módulo local valida una sola propuesta: la correlación de números y la separación anual de series necesitan todavía un futuro repositorio autorizado.

La correspondencia F1/F2, el método por diferencia/sustitución y la causa R4/R5 proceden de las [preguntas frecuentes oficiales sobre procedimientos de facturación](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/preguntas-frecuentes/procedimientos-facturacion.html). Una causa de error en derecho o del artículo 80.1/2/6, concurso o deuda incobrable se rechaza en este modelo: requiere desarrollar R1/R2/R3. R5 solo se usa aquí con un original conservado F2, sin destinatario y con causa no especial declarada; otras causas de simplificadas permanecen fuera de este subconjunto. No se implementa el canje F3.

## Importes y referencias conservadas

El cálculo utiliza las partidas inmutables de `FiscalCalculation`. Los mapas de recargos y retenciones y las listas de bases quedan sin mutación. Para subsanar, la referencia debe aportar el cálculo original conservado: comparar solo las sumas no basta. Se compara también cada cantidad, precio, descuento, tratamiento, tipo, base, cuota, recargo y base de retención; se rechaza una distribución de IVA diferente aunque produzca exactamente el mismo total. La representación local incluye cantidad, precio, descuento, tipo y céntimos de cada partida; no sustituye la definición de una factura fiscal ni el formato del ledger actual.

En el método I se conserva el ajuste firmado. En S, la propuesta contiene el importe nuevo íntegro y los importes originales rectificados separados. Por ejemplo, original de base 100 € + IVA 21 € + recargo 5,20 €, nueva propuesta 80 € + IVA 16,80 €: se conservan base/cuota/recargo originales y el ajuste de total es −29,40 €. Nunca se reescribe el original. Las fechas de operación deben coincidir con la referencia, y la nueva expedición no puede preceder a la original.

Una referencia con identificador y SHA-256 estructural no acredita su origen ni la aceptación por la AEAT. Su autenticación, búsqueda, persistencia y permisos son trabajo pendiente. La subsanación incluye una referencia declarada de la respuesta anterior y la existencia declarada del registro: recepción con errores implica N; rechazo del alta inicial implica X y ausencia de registro; rechazo de la subsanación implica S y registro existente. La matriz proviene del anexo 6.1 de las validaciones AEAT; otros circuitos especiales quedan excluidos. El modelo tampoco permite referencias a documentos rectificativos anteriores: soporta originales F1/F2 y rechaza otros tipos.

El total técnico se define como base + impuesto + recargo. La retención cambia el importe a cobrar y se conserva por separado; no reduce ese total ni la cuota del impuesto. La [FAQ oficial del Pre303, apartado 1.16](https://sede.agenciatributaria.gob.es/static_files/Sede/Tema/IVA/PRE_303/FAQs_Pre303_22v1_5.pdf) recoge el ejemplo de base 200 €, IVA 42 € y retención 30 €: total 242 €, cobro 212 €. El 15 % del ejemplo no se adopta como tarifa legal universal.

Los recargos se declaran por partida. Para IVA 21/10/4 se contrastan recargos 5,2/1,4/0,5; el 1,75 de tabaco requiere una declaración diferenciada. Los pares transitorios de 2022–2024 se acotan por fecha. Una fecha distinta entre cálculo y propuesta se rechaza. La fecha técnica de revisión se aporta explícitamente para mantener el modelo determinista: no admite expedición futura, expedición anterior al 28/10/2024 ni operación anterior a los veinte años previos. No verifica el reloj de un servidor oficial. El redondeo de recargo por partida y retención por base seleccionada es simétrico, mitad alejándose de cero; su futura agrupación XML requiere pruebas adicionales. Las bases de retención no pueden aplicarse dos veces.

Estos pares y las restricciones de tipo se comprobaron en las [validaciones oficiales VERI*FACTU 1.2.2](https://www.agenciatributaria.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/Validaciones_Errores_Veri-Factu.pdf), y los tipos actuales de recargo se contrastaron también con las [instrucciones oficiales del modelo 303 de 2026](https://sede.agenciatributaria.gob.es/Sede/todas-gestiones/impuestos-tasas/iva/modelo-303-iva-autoliquidacion_/instrucciones-2026/instrucciones-02-12-2t-4t-2026.html). La aplicación legal por producto y régimen continúa requiriendo datos revisados de cada cliente.

## Identificación y anticipos

La enumeración de países copia los 246 valores del `CountryType2` del XSD fijado en `tool/fixtures/aeat/SuministroInformacion.xsd`; una prueba la compara con ese archivo. Los códigos especiales del esquema se conservan sin tratarlos como territorios fiscales. Fuente: [esquemas oficiales](https://www.agenciatributaria.es/AEAT.desarrolladores/Desarrolladores/_menu_/Documentacion/Sistemas_Informaticos_de_Facturacion_y_Sistemas_VERI_FACTU/Esquemas_de_los_servicios_web/Esquemas_de_los_servicios_web.html).

Para el tipo 02 se comprueba la estructura publicada del NIF-IVA: prefijo coherente, longitudes y caracteres, incluido GR con prefijo EL. GB/XI necesita reglas históricas por fecha y queda sin soporte. Para España solo se admiten los tipos alternativos 03/07; 07 se limita a España. Son restricciones estructurales de las [validaciones oficiales](https://www.agenciatributaria.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/Validaciones_Errores_Veri-Factu.pdf), no comprobaciones de alta tributaria.

El anticipo representa solo el importe recibido que origina la propuesta. Se investigó la obligación y su excepción para determinadas entregas intracomunitarias en la [página oficial sobre obligación de facturar](https://www3.agenciatributaria.gob.es/Sede/iva/facturacion-registro/facturacion-iva/obligacion-facturar.html). No se automatizan el devengo de supuestos especiales, la factura final ni la imputación contable del anticipo.

## Estado y validación

- **Investigado:** fuentes BOE/AEAT citadas; identificación, simplificación, rectificación, anticipos y cálculos separados.
- **Implementado localmente:** módulo puro y 23 pruebas dedicadas de límites, negativas, referencias, IDOtro, fechas, importes y bloqueos de activación. La revisión lógica independiente detectó tres carencias (fecha técnica, distinción de rechazos y desglose de subsanaciones), corregidas con regresiones específicas. Análisis estático sin incidencias. La ejecución Flutter se registra desde el proceso principal: el agente que redactó el módulo no puede abrir el socket local del ejecutor de pruebas.
- **Persistencia/integración pendientes:** formato nuevo del ledger, repositorio de originales autorizado, correlación/series, UI, copia/restauración y XML de estos casos. No se han afirmado pruebas servidor ni integración alojada para este módulo.
- **Validación oficial pendiente:** identificación censal, límites de negocio completos, certificados/representación, declaraciones de fabricante, envío oficial y respuestas. No se activa emisión, aunque un cálculo o un XML técnico resulte correcto.
- **Casos excluidos hasta implementación:** R1/R2/R3, F3, rectificación de cualificadas, rectificaciones de múltiples originales o de una rectificativa, exención/inversión/no sujeción, IGIC/IPSI, regímenes especiales, operaciones con fecha futura, agrupación XML de recargos/retenciones y cierre completo de anticipos.

La sede AEAT enlaza una [comunicación de Hacienda del 05/10/2026 sobre una previsión de ampliación del plazo SIF](https://www.hacienda.gob.es/sgt/gabsehacienda/nota-informativa-verifactu.pdf). Es una previsión: este bloque no modifica fechas de obligación ni habilita facturación por ella. Cualquier adaptación del calendario requiere comprobar la norma publicada aplicable.
