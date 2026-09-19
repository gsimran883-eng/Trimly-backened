package com.clipsnap.editor

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.clipsnap.editor.ai.ClipSnapAIEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
	private val aiEngine by lazy { ClipSnapAIEngine() }

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"clipsnap/ai",
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"segmentSubject" -> {
					val imageBytes = call.argument<ByteArray>("imageBytes")
					if (imageBytes == null) {
						result.error("INVALID_ARGS", "imageBytes is required", null)
						return@setMethodCallHandler
					}

					val bitmap = imageBytes.decodeBitmap()
					if (bitmap == null) {
						result.error("DECODE_FAILED", "Failed to decode input image bytes", null)
						return@setMethodCallHandler
					}

					aiEngine.processFrame(bitmap) { subjectBitmap ->
						if (subjectBitmap == null) {
							result.error("SEGMENTATION_FAILED", "ML Kit subject segmentation failed", null)
						} else {
							result.success(
								mapOf(
									"imageBytes" to subjectBitmap.toPngBytes(),
									"width" to subjectBitmap.width,
									"height" to subjectBitmap.height,
								),
							)
						}
					}
				}

				else -> result.notImplemented()
			}
		}
	}

	override fun onDestroy() {
		aiEngine.close()
		super.onDestroy()
	}
}

private fun ByteArray.decodeBitmap(): Bitmap? =
	BitmapFactory.decodeByteArray(this, 0, size)

private fun Bitmap.toPngBytes(): ByteArray {
	val output = ByteArrayOutputStream()
	compress(Bitmap.CompressFormat.PNG, 100, output)
	return output.toByteArray()
}