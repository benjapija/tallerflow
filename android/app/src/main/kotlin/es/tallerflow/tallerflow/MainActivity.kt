package es.tallerflow.tallerflow

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "es.tallerflow/local_text")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                try {
                    val file = File(path ?: "").canonicalFile
                    val root = cacheDir.canonicalFile.path + File.separator
                    require(path != null && file.path.startsWith(root))
                    require(file.isFile && file.length() in 1L..16777216L)
                    val image = InputImage.fromFilePath(applicationContext, Uri.fromFile(file))
                    val reader = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                    reader.process(image)
                        .addOnSuccessListener { text ->
                            if (text.text.length <= 4000) result.success(text.text)
                            else result.error("TEXT_LIMIT", "Captura demasiado extensa", null)
                        }
                        .addOnFailureListener { result.error("READ_FAILED", "No se pudo leer la imagen", null) }
                        .addOnCompleteListener { reader.close() }
                } catch (_: Exception) {
                    result.error("IMAGE_INVALID", "Imagen privada no disponible", null)
                }
            }
    }
}
