package com.clipsnap.editor.ai

import android.graphics.Bitmap
import android.os.Build
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions

class ClipSnapAIEngine {

    companion object {
        @JvmStatic
        fun isSegmentationSupported(apiLevel: Int): Boolean = apiLevel < 35
    }

    private val options =
        SubjectSegmenterOptions.Builder()
            .enableForegroundBitmap()
            .enableForegroundConfidenceMask()
            .enableMultipleSubjects(
                SubjectSegmenterOptions.SubjectResultOptions.Builder()
                    .enableConfidenceMask()
                    .enableSubjectBitmap()
                    .build(),
            )
            .build()

    private val segmenter: SubjectSegmenter? =
        if (isSegmentationSupported(Build.VERSION.SDK_INT)) {
            SubjectSegmentation.getClient(options)
        } else {
            null
        }

    fun processFrame(bitmap: Bitmap, onResult: (Bitmap?) -> Unit) {
        if (segmenter == null) {
            onResult(null)
            return
        }

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

    fun close() {
        segmenter?.close()
    }
}
