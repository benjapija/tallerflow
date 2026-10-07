# Pedidos manuales, recepciones y devoluciones

En Catálogo, administrador y oficina con permiso de costes pueden crear un pedido al proveedor. Incluye referencia, fecha prevista, motivo, reparación vinculada opcional y varias partidas. Cada partida conserva artículo, unidad, contenido por envase, envases solicitados y coste por unidad antes de impuestos. Crear el pedido no cambia existencias ni lo envía al proveedor.

Recibir permite cantidades parciales e identifica el albarán y la comprobación física. Dos envases de cinco litros representan diez litros. Se rechazan conversiones que necesiten más de tres decimales; el movimiento conserva el coste original aunque cambie el catálogo. Las devoluciones al proveedor requieren cantidad recibida y disponible sin reservas. Conservan el pedido y la recepción original. No generan automáticamente un cobro o abono bancario.

El servidor aplica recepción, stock, auditoría y justificante de comando en una transacción. El mismo comando se puede reintentar tras perder la respuesta. La revisión del almacén impide aceptar un movimiento calculado sobre datos antiguos. Los operarios no reciben proveedores ni costes de compras; los permisos también se comprueban en el servidor.

Sin conexión se conserva un comando pendiente, incluyendo su identificador y fecha. Las existencias muestran solo lo confirmado. Tras sincronizar hay que revisar su resultado antes de registrar otro movimiento. La copia local conserva el pendiente y la copia completa del servidor incluye inventory_state, comandos, stock y auditoría. Restauración comprobada en bases independientes, incluidos rechazo de una copia incompleta y recuperación de copias anteriores.

Una devolución no vuelve a abrir la cantidad pendiente del pedido original: una reposición requiere otro pedido. No hay envío por API, conciliación de facturas de proveedor, cambios de unidad de un pedido existente ni valoración contable de existencias. Las piezas aportadas por el cliente, reservas, consumos y devoluciones al almacén siguen su circuito existente en la reparación.

Comprobaciones: trece pruebas Flutter específicas; ocho PostgreSQL de compras, recuperación completa en tres bases locales y diez SQL alojadas en cada proyecto gratuito. Auth HTTP y uso manual de la pantalla en clientes físicos siguen pendientes. La demo del navegador usa datos ficticios.
