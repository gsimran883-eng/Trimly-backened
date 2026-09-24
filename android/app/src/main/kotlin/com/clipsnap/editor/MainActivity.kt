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

					val bitmap = imageBytes.decodeBitmap(maxDimension = 1280)
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

				"generateRamboComposite" -> {
					val imageBytes = call.argument<ByteArray>("imageBytes")
					val backgroundBytes = call.argument<ByteArray>("backgroundBytes")
					if (imageBytes == null || backgroundBytes == null) {
						result.error("INVALID_ARGS", "imageBytes and backgroundBytes are required", null)
						return@setMethodCallHandler
					}

					val bitmap = imageBytes.decodeBitmap(maxDimension = 1280)
					val background = backgroundBytes.decodeBitmap(maxDimension = 1920)
					if (bitmap == null || background == null) {
						result.error("DECODE_FAILED", "Failed to decode composite inputs", null)
						return@setMethodCallHandler
					}

					aiEngine.generateRamboComposite(bitmap, background) { composite ->
						bitmap.recycle()
						background.recycle()
						if (composite == null) {
							result.error("COMPOSITE_FAILED", "Local Rambo composition failed", null)
						} else {
							result.success(
								mapOf(
									"imageBytes" to composite.toPngBytes(),
									"width" to composite.width,
									"height" to composite.height,
								),
							)
						}
					}
				}

				"createFacePreserveMask" -> {
					val imageBytes = call.argument<ByteArray>("imageBytes")
					if (imageBytes == null) {
						result.error("INVALID_ARGS", "imageBytes is required", null)
						return@setMethodCallHandler
					}
					val bitmap = imageBytes.decodeBitmap(maxDimension = 1280)
					if (bitmap == null) {
						result.error("DECODE_FAILED", "Failed to decode source image", null)
						return@setMethodCallHandler
					}
					aiEngine.createFacePreserveMask(bitmap) { mask ->
						bitmap.recycle()
						if (mask == null) {
							result.error("FACE_NOT_FOUND", "No clear face was detected", null)
						} else {
							result.success(mapOf("imageBytes" to mask.toPngBytes()))
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

private fun ByteArray.decodeBitmap(maxDimension: Int): Bitmap? {
	val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
	BitmapFactory.decodeByteArray(this, 0, size, bounds)
	if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
		return null
	}

	val options = BitmapFactory.Options().apply {
		inSampleSize = ClipSnapAIEngine.calculateInSampleSize(
			bounds.outWidth,
			bounds.outHeight,
			maxDimension,
		)
		inPreferredConfig = Bitmap.Config.ARGB_8888
	}
	return BitmapFactory.decodeByteArray(this, 0, size, options)
}

private fun Bitmap.toPngBytes(): ByteArray {
	val output = ByteArrayOutputStream()
	compress(Bitmap.CompressFormat.PNG, 100, output)
	return output.toByteArray()
}