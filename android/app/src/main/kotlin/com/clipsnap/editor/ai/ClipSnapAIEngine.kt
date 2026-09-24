package com.clipsnap.editor.ai

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

class ClipSnapAIEngine {

    companion object {
        @JvmStatic
        fun isSegmentationSupported(apiLevel: Int): Boolean = apiLevel >= 24

        @JvmStatic
        fun calculateInSampleSize(width: Int, height: Int, maxDimension: Int): Int {
            var sampleSize = 1
            while (max(width / sampleSize, height / sampleSize) > maxDimension) {
                sampleSize *= 2
            }
            return sampleSize
        }
    }

    private val options =
        SubjectSegmenterOptions.Builder()
            .enableForegroundBitmap()
            .build()

    private val segmenter: SubjectSegmenter = SubjectSegmentation.getClient(options)
    private val faceDetector: FaceDetector =
        FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                .setMinFaceSize(0.12f)
                .build(),
        )

    fun processFrame(bitmap: Bitmap, onResult: (Bitmap?) -> Unit) {
        val image = InputImage.fromBitmap(bitmap, 0)

        segmenter
            .process(image)
            .addOnSuccessListener { result ->
                val subjectBitmap = result.foregroundBitmap
                onResult(subjectBitmap)
            }
            .addOnFailureListener {
                onResult(null)
            }
    }

    fun generateRamboComposite(
        source: Bitmap,
        background: Bitmap,
        onResult: (Bitmap?) -> Unit,
    ) {
        val image = InputImage.fromBitmap(source, 0)
        segmenter
            .process(image)
            .addOnSuccessListener { segmentation ->
                val foreground = segmentation.foregroundBitmap
                if (foreground == null) {
                    onResult(null)
                    return@addOnSuccessListener
                }
                faceDetector
                    .process(image)
                    .addOnSuccessListener { faces ->
                        runCatching {
                            composeRamboPoster(source, foreground, background, faces)
                        }.onSuccess(onResult).onFailure { onResult(null) }
                    }.addOnFailureListener {
                        runCatching {
                            composeRamboPoster(source, foreground, background, emptyList())
                        }.onSuccess(onResult).onFailure { onResult(null) }
                    }
            }.addOnFailureListener {
                onResult(null)
            }
    }

    fun createFacePreserveMask(bitmap: Bitmap, onResult: (Bitmap?) -> Unit) {
        faceDetector
            .process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { faces ->
                val face = faces.maxByOrNull {
                    it.boundingBox.width() * it.boundingBox.height()
                }
                if (face == null) {
                    onResult(null)
                    return@addOnSuccessListener
                }

                val mask = Bitmap.createBitmap(
                    bitmap.width,
                    bitmap.height,
                    Bitmap.Config.ARGB_8888,
                )
                val canvas = Canvas(mask)
                canvas.drawColor(Color.WHITE)
                val bounds = RectF(face.boundingBox)
                bounds.inset(-bounds.width() * 0.30f, -bounds.height() * 0.42f)
                canvas.drawOval(
                    bounds,
                    Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK },
                )
                onResult(mask)
            }.addOnFailureListener { onResult(null) }
    }

    private fun composeRamboPoster(
        source: Bitmap,
        foreground: Bitmap,
        background: Bitmap,
        faces: List<Face>,
    ): Bitmap {
        val width = 1080
        val height = 1920
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

        canvas.drawBitmap(background, centerCropMatrix(background, width, height), paint)
        drawBattleAtmosphere(canvas, width, height, behindSubject = true)

        val subjectMatrix = centerCropMatrix(source, width, height)
        canvas.drawBitmap(foreground, subjectMatrix, paint)

        val largestFace = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
        val face = if (largestFace == null) {
            RectF(390f, 410f, 690f, 710f)
        } else {
            RectF(largestFace.boundingBox).also(subjectMatrix::mapRect)
        }
        drawCommandoWardrobe(canvas, face, width, height)
        drawBattleAtmosphere(canvas, width, height, behindSubject = false)
        drawCinematicFinish(canvas, width, height)
        return output
    }

    private fun centerCropMatrix(bitmap: Bitmap, targetWidth: Int, targetHeight: Int): Matrix {
        val scale = max(
            targetWidth.toFloat() / bitmap.width,
            targetHeight.toFloat() / bitmap.height,
        )
        val offsetX = (targetWidth - bitmap.width * scale) / 2f
        val offsetY = (targetHeight - bitmap.height * scale) / 2f
        return Matrix().apply {
            setScale(scale, scale)
            postTranslate(offsetX, offsetY)
        }
    }

    private fun drawCommandoWardrobe(canvas: Canvas, face: RectF, width: Int, height: Int) {
        val faceWidth = face.width().coerceAtLeast(130f)
        val faceHeight = face.height().coerceAtLeast(150f)
        val centerX = face.centerX()
        val shoulderY = face.bottom + faceHeight * 0.20f
        val torsoBottom = min(height * 0.91f, face.bottom + faceHeight * 4.75f)
        val left = max(24f, centerX - faceWidth * 2.05f)
        val right = min(width - 24f, centerX + faceWidth * 2.05f)

        val vest = Path().apply {
            moveTo(left, shoulderY + faceHeight * 0.42f)
            lineTo(centerX - faceWidth * 0.58f, shoulderY)
            quadTo(centerX, shoulderY + faceHeight * 0.78f, centerX + faceWidth * 0.58f, shoulderY)
            lineTo(right, shoulderY + faceHeight * 0.42f)
            lineTo(right - faceWidth * 0.24f, torsoBottom)
            lineTo(left + faceWidth * 0.24f, torsoBottom)
            close()
        }
        val vestPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                left,
                shoulderY,
                right,
                torsoBottom,
                intArrayOf(Color.rgb(37, 43, 37), Color.rgb(8, 12, 10), Color.rgb(24, 31, 24)),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawPath(vest, vestPaint)

        val seam = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(210, 100, 112, 87)
            style = Paint.Style.STROKE
            strokeWidth = max(4f, faceWidth * 0.025f)
        }
        canvas.drawPath(vest, seam)

        val strapPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(48, 61, 42) }
        val strapWidth = faceWidth * 0.23f
        canvas.save()
        canvas.rotate(-11f, centerX - faceWidth * 0.75f, shoulderY)
        canvas.drawRoundRect(
            centerX - faceWidth * 0.92f,
            shoulderY - faceHeight * 0.08f,
            centerX - faceWidth * 0.92f + strapWidth,
            torsoBottom - faceHeight * 0.28f,
            12f,
            12f,
            strapPaint,
        )
        canvas.restore()
        canvas.save()
        canvas.rotate(11f, centerX + faceWidth * 0.75f, shoulderY)
        canvas.drawRoundRect(
            centerX + faceWidth * 0.69f,
            shoulderY - faceHeight * 0.08f,
            centerX + faceWidth * 0.69f + strapWidth,
            torsoBottom - faceHeight * 0.28f,
            12f,
            12f,
            strapPaint,
        )
        canvas.restore()

        val pouchPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(58, 70, 45) }
        val pouchTop = face.bottom + faceHeight * 2.45f
        repeat(3) { index ->
            val pouchWidth = faceWidth * 0.65f
            val gap = faceWidth * 0.12f
            val pouchLeft = centerX - (pouchWidth * 1.5f + gap) + index * (pouchWidth + gap)
            canvas.drawRoundRect(
                pouchLeft,
                pouchTop,
                pouchLeft + pouchWidth,
                pouchTop + faceHeight * 0.58f,
                14f,
                14f,
                pouchPaint,
            )
            canvas.drawLine(
                pouchLeft + 8f,
                pouchTop + faceHeight * 0.16f,
                pouchLeft + pouchWidth - 8f,
                pouchTop + faceHeight * 0.16f,
                seam,
            )
        }

        val headbandPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                face.left,
                face.top,
                face.right,
                face.top,
                Color.rgb(20, 24, 20),
                Color.rgb(75, 82, 61),
                Shader.TileMode.CLAMP,
            )
        }
        val headbandTop = face.top + faceHeight * 0.13f
        canvas.drawRoundRect(
            face.left - faceWidth * 0.12f,
            headbandTop,
            face.right + faceWidth * 0.12f,
            headbandTop + faceHeight * 0.16f,
            10f,
            10f,
            headbandPaint,
        )
        val tie = Path().apply {
            moveTo(face.right + faceWidth * 0.04f, headbandTop + faceHeight * 0.08f)
            lineTo(face.right + faceWidth * 0.78f, headbandTop + faceHeight * 0.20f)
            lineTo(face.right + faceWidth * 0.12f, headbandTop + faceHeight * 0.25f)
            close()
        }
        canvas.drawPath(tie, headbandPaint)

        drawWeaponProp(canvas, face, width, height)
    }

    private fun drawWeaponProp(canvas: Canvas, face: RectF, width: Int, height: Int) {
        val faceHeight = face.height().coerceAtLeast(150f)
        val y = min(height * 0.79f, face.bottom + faceHeight * 3.10f)
        val metal = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                80f,
                y,
                width - 60f,
                y,
                intArrayOf(Color.rgb(18, 24, 23), Color.rgb(84, 99, 91), Color.rgb(15, 19, 18)),
                null,
                Shader.TileMode.CLAMP,
            )
        }
        val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(220, 139, 153, 133)
            style = Paint.Style.STROKE
            strokeWidth = 5f
        }
        val body = RectF(170f, y, width - 245f, y + faceHeight * 0.52f)
        canvas.drawRoundRect(body, 18f, 18f, metal)
        canvas.drawRoundRect(body, 18f, 18f, edge)
        canvas.drawRect(width - 260f, y + faceHeight * 0.12f, width - 45f, y + faceHeight * 0.25f, metal)
        canvas.drawRect(width - 65f, y + faceHeight * 0.09f, width - 24f, y + faceHeight * 0.29f, metal)
        canvas.drawRoundRect(
            90f,
            y + faceHeight * 0.11f,
            205f,
            y + faceHeight * 0.38f,
            18f,
            18f,
            metal,
        )
        canvas.drawRoundRect(
            face.centerX() - face.width() * 0.28f,
            y + faceHeight * 0.46f,
            face.centerX() + face.width() * 0.30f,
            y + faceHeight * 1.18f,
            14f,
            14f,
            metal,
        )
        val detail = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(9, 13, 12) }
        repeat(7) { index ->
            canvas.drawCircle(245f + index * 78f, y + faceHeight * 0.18f, 11f, detail)
        }
    }

    private fun drawBattleAtmosphere(
        canvas: Canvas,
        width: Int,
        height: Int,
        behindSubject: Boolean,
    ) {
        val random = Random(if (behindSubject) 41 else 73)
        if (behindSubject) {
            val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = RadialGradient(
                    width * 0.82f,
                    height * 0.58f,
                    width * 0.38f,
                    Color.argb(180, 255, 91, 28),
                    Color.TRANSPARENT,
                    Shader.TileMode.CLAMP,
                )
            }
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), glow)
        }
        val rain = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(if (behindSubject) 70 else 105, 190, 225, 220)
            strokeWidth = if (behindSubject) 2f else 3f
        }
        repeat(if (behindSubject) 95 else 55) {
            val x = random.nextFloat() * width
            val y = random.nextFloat() * height
            val length = 28f + random.nextFloat() * 72f
            canvas.drawLine(x, y, x - length * 0.18f, y + length, rain)
        }
        if (!behindSubject) {
            val ember = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(255, 126, 54) }
            repeat(36) {
                val x = random.nextFloat() * width
                val y = height * 0.32f + random.nextFloat() * height * 0.60f
                canvas.drawCircle(x, y, 2f + random.nextFloat() * 5f, ember)
            }
        }
    }

    private fun drawCinematicFinish(canvas: Canvas, width: Int, height: Int) {
        val grade = Paint().apply { color = Color.argb(34, 0, 78, 75) }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), grade)
        val vignette = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = RadialGradient(
                width / 2f,
                height * 0.48f,
                height * 0.72f,
                intArrayOf(Color.TRANSPARENT, Color.argb(35, 0, 0, 0), Color.argb(205, 0, 0, 0)),
                floatArrayOf(0f, 0.63f, 1f),
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), vignette)
    }

    fun close() {
        segmenter.close()
        faceDetector.close()
    }
}
