# Facturación española: requisitos por confirmar

Revisión del 7 de octubre de 2026. TallerFlow produce presupuestos, notas y registros de cobro; el módulo fiscal definitivo continúa pendiente. España y la sustitución del papel están confirmadas.

## Normativa consultada

Los plazos generales de adaptación al reglamento de sistemas informáticos de facturación son 1 de enero de 2027 para contribuyentes del Impuesto sobre Sociedades y 1 de julio de 2027 para los demás obligados incluidos en su ámbito. La aplicabilidad concreta depende del taller. Fuentes: [AEAT](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/preguntas-frecuentes.html?faqId=76bb77fe52572910VgnVCM100000dc381e0aRCRD), [Real Decreto-ley 15/2025](https://www.boe.es/buscar/doc.php?id=BOE-A-2025-24446).

La factura electrónica entre empresas y profesionales tiene su propio desarrollo en el [Real Decreto 238/2026](https://www.boe.es/buscar/doc.php?id=BOE-A-2026-7295). Su calendario se cuenta desde la orden que desarrolla la solución pública: doce meses para quienes superen ocho millones de euros de volumen de operaciones y veinticuatro para el resto, conforme a los términos de la norma.

La [Orden HAC/1028/2026](https://www.boe.es/buscar/doc.php?id=BOE-A-2026-20587), publicada el 5 de octubre, entró en vigor el día 6. Por tanto, el cómputo anterior conduce al 6 de octubre de 2027 o 2028, respectivamente; es una derivación del calendario legal, sin asignar todavía un plazo al taller. La solución pública está prevista con acceso gratuito y utiliza UBL/EN 16931. Esa previsión no demuestra que TallerFlow esté integrado o validado.

El Ministerio de Hacienda comunicó el 5 de octubre una **previsión** de alineación de las obligaciones pendientes de SIF con octubre de 2028. La nota indica que la modificación aún debe aprobarse; no sustituye por sí misma los plazos aprobados que la AEAT sigue publicando. Se conserva esta distinción hasta verificar la norma que efectúe el cambio. Fuentes: [comunicación de Hacienda](https://www.hacienda.gob.es/sgt/gabsehacienda/nota-informativa-verifactu.pdf), [nota publicada](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu.html), [plazos aprobados según AEAT](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/nota-informativa-ampliacion-plazo-adaptacion-facturacion.html).

## Información imprescindible del taller

Se solicitó autónomo/sociedad, provincia, SII y tipos de destinatario. Después hacen falta denominación/NIF y domicilio fiscal aplicables, régimen tributario, series y última numeración utilizada, tipos de factura y rectificación, y acreditación para los servicios que correspondan. El volumen de operaciones condiciona el calendario B2B. El ámbito foral debe comprobarse si la provincia lo requiere.

## Trabajo pendiente y coste

Con esa información se podrá elegir el circuito fiscal, implementar sus registros y formatos, y validar numeración, correcciones, conservación, permisos y reintentos contra el entorno oficial que corresponda. No se ha contratado un proveedor ni comprado un certificado. La consulta normativa es gratuita; cualquier servicio externo debe tener gratuidad confirmada antes de utilizarlo. Las credenciales y certificados se conectarían por el servicio adecuado, sin enviarlos al chat ni incluirlos en las aplicaciones.

No se transforma una nota existente en factura ni se recalculan documentos emitidos. Los cobros actuales conservan sus referencias y auditoría hasta disponer de la emisión fiscal validada.
