# Facturación española: producto para distintos talleres

Revisión del 7 de octubre de 2026. TallerFlow produce presupuestos, notas y registros de cobro; el módulo fiscal definitivo continúa pendiente. España y la sustitución del papel están confirmadas.

## Normativa consultada

Los plazos generales de adaptación al reglamento de sistemas informáticos de facturación son 1 de enero de 2027 para contribuyentes del Impuesto sobre Sociedades y 1 de julio de 2027 para los demás obligados incluidos en su ámbito. La aplicabilidad concreta depende del taller. Fuentes: [AEAT](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/preguntas-frecuentes.html?faqId=76bb77fe52572910VgnVCM100000dc381e0aRCRD), [Real Decreto-ley 15/2025](https://www.boe.es/buscar/doc.php?id=BOE-A-2025-24446).

La factura electrónica entre empresas y profesionales tiene su propio desarrollo en el [Real Decreto 238/2026](https://www.boe.es/buscar/doc.php?id=BOE-A-2026-7295). Su calendario se cuenta desde la orden que desarrolla la solución pública: doce meses para quienes superen ocho millones de euros de volumen de operaciones y veinticuatro para el resto, conforme a los términos de la norma.

La [Orden HAC/1028/2026](https://www.boe.es/buscar/doc.php?id=BOE-A-2026-20587), publicada el 5 de octubre, entró en vigor el día 6. Por tanto, el cómputo anterior conduce al 6 de octubre de 2027 o 2028, respectivamente; es una derivación del calendario legal, sin asignar todavía un plazo al taller. La solución pública está prevista con acceso gratuito y utiliza UBL/EN 16931. Esa previsión no demuestra que TallerFlow esté integrado o validado.

El Ministerio de Hacienda comunicó el 5 de octubre una **previsión** de alineación de las obligaciones pendientes de SIF con octubre de 2028. La nota indica que la modificación aún debe aprobarse; no sustituye por sí misma los plazos aprobados que la AEAT sigue publicando. Se conserva esta distinción hasta verificar la norma que efectúe el cambio. Fuentes: [comunicación de Hacienda](https://www.hacienda.gob.es/sgt/gabsehacienda/nota-informativa-verifactu.pdf), [nota publicada](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu.html), [plazos aprobados según AEAT](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/nota-informativa-ampliacion-plazo-adaptacion-facturacion.html).

## Alcance comercial y preparación implementada

El usuario venderá TallerFlow a distintos talleres. Cada taller conserva sus propios usuarios, permisos, tarifas, registros y documentos; la configuración fiscal no se limita a un negocio identificado.

El administrador guarda **Preparación fiscal** con motivo y control de revisión. Incluye autónomo/persona física, sociedad, atribución de rentas u otra forma; territorio común, Canarias, Ceuta, Melilla, Navarra, Álava, Bizkaia y Gipuzkoa; SII sí/no/pendiente; clientes particulares, empresas/profesionales, Administraciones o mixtos; volumen hasta ocho millones inclusive o superior; IVA, IGIC, IPSI u otro/mixto por revisar. Permite dejar datos pendientes. No deduce automáticamente régimen, obligación o plazo.

El perfil conserva `emissionEnabled:false`: no emite ni remite facturas, no altera tarifas, trabajos ni documentos originales. Está auditado, aislado y reservado al administrador; copia formato 13 y restauración independiente probadas. Cinco Flutter/doce PostgreSQL locales; doce SQL con rollback por proyecto alojado, identidades sintéticas. No es validación fiscal.

## Matriz del producto pendiente

| Circuito que debe contemplarse | Información por taller | Trabajo restante |
|---|---|---|
| SIF estatal, modalidad aplicable | Sujeto/ámbito, SII, series, identificación | Emisión, registros, correcciones, cadena, formatos y pruebas oficiales; declaración del fabricante cuando proceda |
| SII | Ámbito, titular, representación | Adaptador, libros, respuestas y reintentos; comprobar exclusiones oficiales |
| Territorios forales | Administración competente y obligaciones | Adaptadores y formatos propios según el caso; no afirmar cobertura estatal universal |
| IVA / IGIC / IPSI | Operación, territorio, tipos/exenciones | Reglas y justificantes; elegir impuesto no aplica un porcentaje |
| B2B electrónico | Destinatario, volumen, interoperabilidad | Formatos, estados y solución aplicable según norma vigente |
| Administraciones públicas | Destinatario y códigos | Entrega al sistema aplicable y comprobación oficial |
| Particulares y rectificaciones | Datos obligatorios, tipo y motivo | Numeración, factura completa/simplificada cuando proceda y rectificaciones con originales conservados |

La matriz identifica desarrollo pendiente. No promete cumplimiento ni conectores disponibles. El núcleo de cálculo y el adaptador estatal sin transmisión ya tienen pruebas locales; quedan persistencia, numeración, rectificativas completas y aceptación oficial. El diseño no queda bloqueado por desconocer datos de un taller particular.

## Alta de cada taller y coste

Cada cliente aportará denominación/NIF, domicilio, administración/régimen, series/última numeración, tipos de factura y representación/certificado aplicables. La obligación y sus plazos se verifican antes de activar emisión. Credenciales mediante servicio autorizado, sin chat ni inclusión en aplicaciones.

No se ha contratado proveedor ni comprado certificado. Investigación, desarrollo y proyectos actuales gratuitos; cualquier coste se consultará. Notas/PDF actuales: **documentos de trabajo**. No se convierten retrospectivamente en factura ni recalculan emitidos; los cobros conservan referencias y auditoría.

## Referencias técnicas confirmadas para continuar el desarrollo

La [AEAT describe el ámbito SIF y exclusiones, incluido SII y residencia foral](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/cuestiones-generales/quienes-estan-obligados-que-operaciones-incluyen.html). El [Gobierno Vasco distingue TicketBAI de las tres haciendas y sus registros de software](https://www.euskadi.eus/ticketbai/); Navarra se mantiene como revisión propia, sin asignarle TicketBAI por analogía.

La [documentación técnica AEAT](https://www3.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/informacion-tecnica/especificaciones-tecnicas-firma-electronica-registros-evento.html) enlaza esquemas, WSDL, validaciones, hash, QR, declaraciones y portal externo de pruebas. Hay material público para avanzar en el motor sin conocer un cliente particular. Quedan implementación y pruebas de cadena/numeración, correcciones, formatos, fallos/reintentos y aislamiento antes de conectar acreditación de un taller. Leer documentación no acredita emisión oficial ni aceptación del servicio.

Como ensayo técnico independiente se han reproducido los tres ejemplos de hash del [PDF enlazado por la AEAT](https://www.agenciatributaria.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/Veri-Factu_especificaciones_huella_hash_registros.pdf): primer alta, alta encadenada y anulación. Los SHA-256 coinciden; evidencia fiscal-hash-official-rehearsal.json. Es una comprobación preparatoria de ejemplos publicados, sin emisión ni llamada al servicio; todavía no existe el motor fiscal integrado.

## Avance técnico de esta ejecución

Núcleo de cálculo exacto por partida y grupos de IVA/IGIC/IPSI/otros, ajustes negativos justificados y lectura del desglose de notas sin cambiar sus originales. Adaptador estatal **local y sin emisión**: huellas de alta/anulación, URL QR solo de pruebas y borradores XML F1/anulación. 17 Flutter nuevas y ocho comprobaciones contra XSD públicos guardados, todas locales; no hay transmisión, numeración oficial ni validación de negocio completa. Véase [MOTOR_FISCAL_EN_DESARROLLO.md](MOTOR_FISCAL_EN_DESARROLLO.md).
