# Cobros y entrega

Oficina abre una nota emitida y registra dinero ya recibido: importe, medio, fecha real, referencia y motivo. El registro no realiza un cargo bancario. Los cálculos utilizan céntimos enteros. No se admiten sobrepagos ni fechas anteriores a la emisión de la nota; los anticipos anteriores a la nota todavía no están incluidos.

Una devolución conserva el cobro original y añade un registro vinculado. Admite devoluciones parciales hasta el importe restante de ese cobro. No altera la nota emitida ni constituye una rectificación fiscal.

La entrega conserva el motivo y el saldo revisado en ese momento. Oficina puede autorizarla con saldo pendiente; entregado no implica pagado. Los cobros posteriores actualizan el saldo actual y conservan esa decisión de entrega.

Sin conexión se conservan los registros cifrados. Un reintento de la misma operación no duplica dinero. Si otra oficina cambia el saldo, el servidor conserva el conflicto para revisión; hay que reconciliar la incidencia antes de registrar otro importe. No deseches un conflicto sin comprobar los movimientos reales.

Las copias completas incluyen registros originales, documentos y auditoría. Los operarios no reciben el detalle personal de cobros o entrega. Este bloque se ha probado con datos ficticios localmente y por SQL alojado; sus pantallas y Auth HTTP nativos siguen pendientes.
