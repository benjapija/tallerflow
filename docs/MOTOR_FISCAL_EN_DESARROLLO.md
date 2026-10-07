# Motor fiscal · documento de trabajo

7 de octubre de 2026. Desarrollo genérico para distintos talleres de España. **Emisión y transmisión desactivadas.** La configuración de preparación no concede autorización fiscal.

## Implementación actual

- Cálculo en céntimos y cantidades de milésimas, sin coma flotante. Descuento antes del impuesto; redondeo simétrico por partida, mitad alejándose de cero. Los grupos suman las cuotas de sus partidas, sin otro redondeo. Es una política aritmética documentada que deberá contrastarse con cada circuito fiscal.
- Grupos distintos para IVA, IGIC, IPSI y otros; tipos explícitos, sin elegirlos por territorio. Exención, inversión y no sujeción requieren motivo y cuota cero. Ajustes negativos necesitan motivo; no se convierten en una rectificación emitida.
- Desglose para oficina de las notas existentes. Lee sus valores guardados, comprueba coherencia y conserva tipos desconocidos de documentos antiguos. No usa el perfil actual para cambiar la naturaleza del impuesto de un documento anterior.
- Primitivas locales del adaptador AEAT: tres ejemplos oficiales SHA-256, concatenación en el orden documentado, hexadecimales en mayúsculas y URL QR únicamente de pruebas, con parámetros codificados. No se añade QR fiscal a notas ni PDF.
- Borradores técnicos XML F1 con destinatario nacional y anulación, identificación explícita de fabricante/instalación, cadena por emisor y huso horario. Sin transporte, certificados, numeración oficial, recibo de aceptación ni emisión. Datos exclusivamente ficticios.
- Se rechaza el uso silencioso del adaptador estatal con SII, territorio desconocido o foral. Esto protege el límite del adaptador; no decide las obligaciones de un cliente.

## Evidencia y fuentes

17 pruebas nuevas de Flutter: aritmética, ajustes, límites, permisos, documentos conservados, tres huellas oficiales, QR, XML, exclusiones y separación de emisores. La batería anterior tenía 243 pruebas. El avance del cliente fiscal y sus reglas se verifica en la batería nueva; consultar el informe actual para no sumar pruebas repetidas.

Diez comprobaciones XML locales, incluyendo dos originales confirmados ficticios y las ocho anteriores: integridad de tres esquemas oficiales guardados, dos registros válidos y rechazo de sistema ausente, impuesto desconocido y decimal con coma. Los XSD se conservan sin modificar, con origen y SHA-256 en `tool/fixtures/aeat/sources.json`; un catálogo local resuelve el esquema de firma de W3C. La validación se ejecuta sin red. **Superar XSD no acredita aceptación por AEAT ni cumplimiento de todas sus validaciones de negocio.**

Fuentes oficiales consultadas:

- [Reglamento de facturación, artículos 6 y 15](https://www.boe.es/buscar/act.php?id=BOE-A-2012-14696): contenido y rectificaciones.
- [Huella AEAT, documento 0.1.2 enlazado](https://www.agenciatributaria.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/Veri-Factu_especificaciones_huella_hash_registros.pdf): entradas y ejemplos publicados.
- [Esquemas del servicio](https://www.agenciatributaria.es/AEAT.desarrolladores/Desarrolladores/_menu_/Documentacion/Sistemas_Informaticos_de_Facturacion_y_Sistemas_VERI_FACTU/Esquemas_de_los_servicios_web/Esquemas_de_los_servicios_web.html): alta, anulación, tipos, grupos y nombres de elementos.
- [QR AEAT, documento 0.5.0](https://www.agenciatributaria.es/static_files/AEAT_Desarrolladores/EEDD/IVA/VERI-FACTU/DetalleEspecificacTecnCodigoQRfactura.pdf): URL y codificación; el adaptador actual solo construye la URL de pruebas.

## Pendientes de desarrollo, independientes de un taller concreto

1. Registro de borradores de ensayo persistente, series separadas, recibos, cadena de integridad y copias formato 14 implementados en servidor. Auth HTTP, recuperación alojada 14 y peticiones superpuestas aprobados; interfaz/cola local e integración XML ya implementadas y probadas localmente. Los originales XML quedan cifrados en el dispositivo y sus copias; su almacenamiento compartido en servidor aún no está implementado. No equivale a numeración, cadena ni continuidad fiscales; véase REGISTRO_BORRADORES_FISCALES.md. El XML sigue siendo local.
2. Facturas completas, simplificadas donde proceda, rectificativas por diferencias/sustitución, subsanaciones, rechazo previo, destinatarios extranjeros, anticipos y regímenes especiales. El módulo puro fiscal_document_rules prepara F1/F2/cualificadas, R4/R5, subsanación con desglose original, extranjeros, anticipos, recargos y retenciones mediante declaración explícita; tiene 23 pruebas dedicadas. Su contrato persistente, interfaz y XML específico siguen pendientes. No habilita facturas ni inferencias tributarias; véase FISCAL_REGLAS_DOCUMENTOS_ENSAYO.md.
3. Validaciones de negocio publicadas por AEAT, respuestas, rechazos y reintentos; transportes y pruebas oficiales. Declaración responsable del fabricante y circuitos de conservación/revisión necesarios antes de activar emisión.
4. Adaptadores SII, territorios forales, B2B electrónico y Administraciones, según sus especificaciones oficiales; el adaptador estatal parcial no equivale a esa cobertura.
5. Documentos fiscales y QR definitivo únicamente después de validar el circuito aplicable. Notas y PDF actuales siguen como documentos de trabajo.

Cada cliente aportará identificación, domicilio, régimen, series y representación al alta. El certificado o medio de identificación requerido se conectará de forma personal y segura cuando el transporte oficial esté preparado; no se solicita en el chat. Se mantienen las restricciones de recursos gratuitos y la IA real desactivada.
