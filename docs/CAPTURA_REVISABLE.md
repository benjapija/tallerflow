# Estado actual de captura · 7 de octubre de 2026

Revisión humana y límites privados conservados. CI 37624370177 (6be045d) aprobó **cinco comprobaciones Android y seis iOS**: lectura ficticia, EXIF, blanco, original externo denegado y archivo ausente; iOS incluye temporal privado. Android usa partición 2 GiB y bash. JSON y registro obligatorios adjuntos. Los tres ZIP descargados/verificados. Cámara, QR y micrófono físicos pendientes; batería local completa: 243 Flutter.

La descripción funcional siguiente sigue vigente. Los párrafos sobre antiguos fallos de compilación son históricos y quedan superados por las compilaciones y ensayos indicados arriba.

---

# Dictado y lectura revisable

En recepción, matrícula y VIN ofrecen «Capturar y revisar texto». El cuaderno ofrece el mismo control en la observación técnica, y el catálogo en la referencia. El borrador permite dictado breve en español y, en Android/iPhone, lectura de texto mediante cámara. Las referencias admiten además códigos EAN, Code 128/39, Data Matrix y QR.

La captura solo rellena el campo después de «He revisado: usar texto». El formulario original necesita su confirmación posterior. Se conserva el texto observado, se ofrecen alternativas cuando hay varios identificadores y no se sustituyen letras dudosas del VIN. Los tiempos, consumos, importes y autorizaciones siguen sus formularios propios: dictar «30 minutos» no suma tiempo a un cronómetro. Cancelar conserva el campo original. No se conserva un archivo de audio; las fotografías temporales del lector se retiran del caché propio, sin borrar originales externos.

La voz utiliza [speech_to_text 7.5.0](https://pub.dev/packages/speech_to_text), licencia BSD-3-Clause. Se solicita reconocimiento en el equipo, en español y durante hasta 45 segundos; la disponibilidad depende del servicio de voz, idiomas y permisos del sistema. Windows está declarado en beta por el mantenedor y requiere validación antes del piloto. No se ha probado un micrófono real ni se solicita permiso al abrir el formulario.

La lectura usa [ML Kit para Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android), con el modelo latino incluido en la aplicación, y [Vision de Apple en iOS](https://developer.apple.com/documentation/vision/vnrecognizetextrequest). Ambos lectores funcionan en el dispositivo. La conexión con Flutter utiliza un canal propio; solo recibe una ruta de caché privada y devuelve texto observado, sin interpretar piezas o diagnósticos. No usa una API remota ni claves. El navegador y Windows mantienen entrada manual y dictado cuando su sistema lo permita. La cámara física y el lector de piezas todavía requieren un equipo.

Doce pruebas específicas cubren alternativas, caracteres inválidos, edición, resultados parciales, cancelación, cierre de la ventana y confirmación en dos pasos. El analizador no presenta incidencias; la batería completa incluye 211 pruebas Flutter. La compilación web aprobada no acredita cámara/micrófono nativo ni permisos de dispositivos.

La revisión manual se comprobó además en navegador, sin encender micrófono ni cámara. El texto llega al campo y conserva la confirmación posterior. La primera compilación iOS con OCR falló al enlazar Pods_Runner; se configura CocoaPods para todas las dependencias de este proyecto mientras los adaptadores ML Kit carecen de SwiftPM. Opción oficial: https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers#turn-off-swiftpm-for-a-single-project. La reparación requiere nueva compilación antes de acreditar iOS.

La inspección del repositorio confirmó la causa de los dos fallos: no se habían publicado ios/Podfile ni los includes de Pods en ios/Flutter/Debug.xcconfig y Release.xcconfig. Se corrige la publicación para incluir esos archivos y excluir configuración generada con rutas del Mac. La nueva ejecución permite compilar únicamente iOS después de todas las pruebas, conservando las compilaciones aprobadas de Windows y Android. No se acredita la reparación hasta terminar ese trabajo.

La ejecución 37589845443 confirmó que publicar Podfile/includes resuelve Pods_Runner. Después falló porque MLImage arm64 estaba compilado para iPhone, no para el simulador. Se retira ese adaptador de iOS y se integra Vision, que respeta la orientación de imagen y devuelve líneas para revisión. Android conserva ML Kit mediante su biblioteca nativa 16.0.1; la documentación oficial confirma el modelo incorporado y mínimo API 23, cubierto por minSdk 24. Se requiere compilar de nuevo ambas plataformas antes de acreditar el cambio.
