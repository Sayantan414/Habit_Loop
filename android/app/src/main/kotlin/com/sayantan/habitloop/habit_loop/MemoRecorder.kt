package com.sayantan.habitloop.habit_loop

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

/**
 * Records one dictation take as a small AAC file (.m4a) for Gemini to
 * transcribe in one go once the user stops, like a voice message.
 *
 * Recording the whole take instead of sending it phrase by phrase gives the
 * transcriber the full context, which matters a lot for Bengali, and costs
 * one request per note.
 */
class MemoRecorder(private val context: Context, private val onLimit: () -> Unit) {
    private companion object {
        const val FILE_NAME = "dictation.m4a"

        /** Well inside Gemini's one-hour limit, and about 5 MB at this rate. */
        const val MAX_DURATION_MS = 20 * 60 * 1000

        const val SAMPLE_RATE = 16_000
        const val BIT_RATE = 32_000
    }

    private var recorder: MediaRecorder? = null
    private var limitReached = false

    private val file get() = File(context.cacheDir, FILE_NAME)

    /** False if the mic can't be opened (e.g. another app is using it). */
    fun start(): Boolean {
        discard()
        limitReached = false
        val next = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        return try {
            next.apply {
                setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioChannels(1)
                setAudioSamplingRate(SAMPLE_RATE)
                setAudioEncodingBitRate(BIT_RATE)
                setMaxDuration(MAX_DURATION_MS)
                setOnInfoListener { _, what, _ ->
                    if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) {
                        limitReached = true
                        onLimit()
                    }
                }
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            recorder = next
            true
        } catch (_: Exception) {
            next.release()
            false
        }
    }

    /**
     * Stops recording and returns the file's path, or null when nothing
     * usable was recorded (or [keep] is false, which deletes it).
     */
    fun stop(keep: Boolean): String? {
        val current = recorder ?: return if (keep && limitReached) existing() else null
        recorder = null
        val finished = try {
            // At the duration limit the recorder has already stopped itself.
            if (!limitReached) current.stop()
            true
        } catch (_: RuntimeException) {
            // Stopped straight after starting: no audio was written.
            false
        } finally {
            current.release()
        }
        if (!keep || !finished) {
            file.delete()
            return null
        }
        return existing()
    }

    fun discard() {
        stop(keep = false)
        file.delete()
    }

    private fun existing(): String? = file.takeIf { it.exists() && it.length() > 0 }?.absolutePath
}
