package com.sayantan.habitloop.habit_loop

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionService
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Voice dictation (`habitloop/speech`), built on [SpeechRecognizer] directly
 * so the app chooses the recognizer instead of taking the phone's default:
 *
 * - **Continuous** (Android 13+, language model downloaded): the on-device
 *   recognizer in a segmented session keeps listening across pauses, works
 *   offline, and only ends after [IDLE_SILENCE_MS] of silence.
 *
 * - **Restart**: otherwise Google's online recognizer (or the phone's
 *   default if the Google app is missing). It ends after every short pause
 *   and Flutter restarts it.
 *
 * The phone's default is often an on-device-only service without Bengali,
 * which is why going through it reported the language as not installed.
 *
 * Google's recognizer beeps every time it starts, which in restart mode
 * means after every pause. While a take is running ([setQuiet]) the media
 * stream is muted, which silences the beep on most phones, and restored
 * afterwards.
 */
class SpeechChannel(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        private const val NAME = "habitloop/speech"
        const val PERMISSION_REQUEST = 0x5EEC
        private const val GOOGLE_APP = "com.google.android.googlequicksearchbox"

        /** A continuous session gives up after this much silence. */
        private const val IDLE_SILENCE_MS = 30_000L

        /** Asked of online recognizers; many ignore it and stop sooner. */
        private const val PAUSE_MS = 4_000L

        /** Lets the recognizer's closing beep play out before sound comes back. */
        private const val UNMUTE_DELAY_MS = 700L

        private const val PREFS = "speech"
        private const val KEY_MUTED = "streams_muted_by_dictation"
        private const val KEY_RINGER = "ringer_before_dictation"

        /**
         * Only media sounds are muted. Notification and system sounds follow
         * the ringer on many phones, so muting them flips the phone to
         * vibrate and back, which itself makes a sound.
         */
        private val QUIET_STREAMS = intArrayOf(AudioManager.STREAM_MUSIC)

        /** How long to wait for the on-device language check before going online. */
        private const val SUPPORT_CHECK_TIMEOUT_MS = 2_000L

        private val LANGUAGE_ERRORS = setOf(
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
        )
    }

    private val app = activity.applicationContext
    private val channel = MethodChannel(messenger, NAME)
    private val handler = Handler(Looper.getMainLooper())

    private var recognizer: SpeechRecognizer? = null
    private var listener: Listener? = null
    private var continuous = false
    private var downloader: SpeechRecognizer? = null
    private var pendingPermission: ((Boolean) -> Unit)? = null

    /** Locales whose on-device model failed this run, so they go online. */
    private val onDeviceFailed = HashSet<String>()

    private val audio = app.getSystemService(AudioManager::class.java)
    private val unmute = Runnable { restoreSound() }

    /** What the last [prepare] found, for the in-app diagnostics line. */
    private var lastProbe = "Not checked yet"

    /** The latest recognizer error and when it came, also for diagnostics. */
    private var lastError: String? = null

    init {
        // The app was killed mid-dictation last time: give the sound back.
        restoreSound()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare(call.argument<String>("locale") ?: "en-IN", result)

                "listen" -> {
                    listen(call.argument<String>("locale") ?: "en-IN")
                    result.success(null)
                }

                "stop" -> {
                    recognizer?.stopListening()
                    result.success(null)
                }

                "downloadLanguage" -> result.success(
                    downloadLanguage(call.argument<String>("locale") ?: "en-IN")
                )

                "setQuiet" -> {
                    setQuiet(call.argument<Boolean>("quiet") ?: false)
                    result.success(null)
                }

                "describe" -> result.success(
                    lastProbe + (lastError?.let { " · last error: $it" } ?: "")
                )

                else -> result.notImplemented()
            }
        }
    }

    fun onPermissionResult(granted: Boolean) {
        pendingPermission?.invoke(granted)
        pendingPermission = null
    }

    fun dispose() {
        handler.removeCallbacks(unmute)
        restoreSound()
        listener = null
        recognizer?.destroy()
        recognizer = null
        downloader?.destroy()
        downloader = null
    }

    // ---- Beep muting --------------------------------------------------------

    private fun setQuiet(quiet: Boolean) {
        handler.removeCallbacks(unmute)
        if (!quiet) {
            handler.postDelayed(unmute, UNMUTE_DELAY_MS)
            return
        }
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val muted = prefs.getStringSet(KEY_MUTED, emptySet())!!.toMutableSet()
        if (!prefs.contains(KEY_RINGER)) {
            prefs.edit().putInt(KEY_RINGER, audio.ringerMode).apply()
        }
        for (stream in QUIET_STREAMS) {
            // Already muted by the user (or by us): leave it as it is.
            if (audio.isStreamMute(stream)) continue
            try {
                audio.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, 0)
                muted.add(stream.toString())
            } catch (_: SecurityException) {
                // Do Not Disturb policy can forbid it; that tone then stays.
            }
        }
        prefs.edit().putStringSet(KEY_MUTED, muted).apply()
    }

    /** Unmutes only what dictation muted, never a stream the user silenced. */
    private fun restoreSound() {
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val muted = prefs.getStringSet(KEY_MUTED, emptySet())!!
        for (stream in muted.mapNotNull { it.toIntOrNull() }) {
            try {
                audio.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0)
            } catch (_: SecurityException) {
            }
        }
        // Builds that also muted notification and system sounds could leave
        // the phone on vibrate; switch it back.
        val ringer = prefs.getInt(KEY_RINGER, -1)
        if (ringer == AudioManager.RINGER_MODE_NORMAL && audio.ringerMode == AudioManager.RINGER_MODE_VIBRATE) {
            try {
                audio.ringerMode = AudioManager.RINGER_MODE_NORMAL
            } catch (_: SecurityException) {
            }
        }
        prefs.edit().remove(KEY_MUTED).remove(KEY_RINGER).apply()
    }

    // ---- Setup -------------------------------------------------------------

    /**
     * Asks for the mic if needed, then picks a mode for [locale]. Replies
     * `{ available, continuous, canDownload, problem }`.
     */
    private fun prepare(locale: String, result: MethodChannel.Result) {
        withMicPermission { granted ->
            if (!granted) {
                result.success(mapOf("available" to false, "problem" to "permission"))
                return@withMicPermission
            }
            probe(locale) { onDevice ->
                val online = SpeechRecognizer.isRecognitionAvailable(app)
                continuous = onDevice == OnDevice.INSTALLED
                val canDownload = onDevice == OnDevice.DOWNLOADABLE
                lastProbe = "Android ${Build.VERSION.SDK_INT} · $locale · " +
                    "on-device: ${onDevice.name.lowercase()} · " +
                    "online: ${onlineServiceName() ?: "none"} · " +
                    "mode: ${if (continuous) "continuous" else "restart"}"
                result.success(
                    mapOf(
                        "available" to (continuous || online),
                        "continuous" to continuous,
                        "canDownload" to canDownload,
                        "problem" to when {
                            continuous || online -> null
                            canDownload -> "needs_download"
                            else -> "unavailable"
                        },
                    )
                )
            }
        }
    }

    private fun withMicPermission(then: (Boolean) -> Unit) {
        val granted = activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            then(true)
            return
        }
        pendingPermission = then
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
    }

    private enum class OnDevice { INSTALLED, DOWNLOADABLE, DOWNLOADING, UNSUPPORTED }

    /** Whether [locale] can run on the on-device recognizer (Android 13+). */
    private fun probe(locale: String, then: (OnDevice) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            locale in onDeviceFailed ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(app)
        ) {
            then(OnDevice.UNSUPPORTED)
            return
        }

        val checker = SpeechRecognizer.createOnDeviceSpeechRecognizer(app)
        var answered = false
        fun answer(value: OnDevice) {
            if (answered) return
            answered = true
            checker.destroy()
            then(value)
        }
        // Some recognizers never answer; don't keep the mic button waiting.
        handler.postDelayed({ answer(OnDevice.UNSUPPORTED) }, SUPPORT_CHECK_TIMEOUT_MS)

        checker.checkRecognitionSupport(
            recognizerIntent(locale),
            activity.mainExecutor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    answer(
                        when {
                            support.installedOnDeviceLanguages.matches(locale) -> OnDevice.INSTALLED
                            support.pendingOnDeviceLanguages.matches(locale) -> OnDevice.DOWNLOADING
                            support.supportedOnDeviceLanguages.matches(locale) -> OnDevice.DOWNLOADABLE
                            else -> OnDevice.UNSUPPORTED
                        }
                    )
                }

                override fun onError(error: Int) = answer(OnDevice.UNSUPPORTED)
            },
        )
    }

    /** Matches `bn-IN` against `bn-IN`, `bn_IN` or plain `bn`. */
    private fun List<String>.matches(locale: String): Boolean {
        val wanted = Locale.forLanguageTag(locale)
        return any {
            val have = Locale.forLanguageTag(it.replace('_', '-'))
            have.language == wanted.language &&
                (have.country.isEmpty() || have.country == wanted.country)
        }
    }

    /** Starts the system download of [locale]'s offline model; false if unsupported. */
    private fun downloadLanguage(locale: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(app)
        ) {
            return false
        }
        downloader?.destroy()
        downloader = SpeechRecognizer.createOnDeviceSpeechRecognizer(app).also {
            it.triggerModelDownload(recognizerIntent(locale))
        }
        onDeviceFailed.remove(locale)
        return true
    }

    /** Google's recognition service if the Google app is installed. */
    private fun googleService(): ComponentName? =
        app.packageManager
            .queryIntentServices(Intent(RecognitionService.SERVICE_INTERFACE), 0)
            .firstOrNull { it.serviceInfo.packageName == GOOGLE_APP }
            ?.serviceInfo
            ?.let { ComponentName(it.packageName, it.name) }

    private fun onlineServiceName(): String? =
        googleService()?.packageName
            ?: if (SpeechRecognizer.isRecognitionAvailable(app)) "default" else null

    // ---- Listening ---------------------------------------------------------

    private fun recognizerIntent(locale: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, app.packageName)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        }

    private fun listen(locale: String) {
        listener = null
        recognizer?.destroy()

        val intent = recognizerIntent(locale)
        val next = if (continuous && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            // Keep going across pauses; end only after a long silence.
            intent.putExtra(
                RecognizerIntent.EXTRA_SEGMENTED_SESSION,
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
            )
            intent.putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                IDLE_SILENCE_MS,
            )
            SpeechRecognizer.createOnDeviceSpeechRecognizer(app)
        } else {
            intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, PAUSE_MS)
            // Undocumented: asks Google's recognizer for its keyboard-style
            // dictation, which waits longer on pauses. Others ignore it.
            intent.putExtra("android.speech.extra.DICTATION_MODE", true)
            intent.putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                PAUSE_MS,
            )
            googleService()?.let { SpeechRecognizer.createSpeechRecognizer(app, it) }
                ?: SpeechRecognizer.createSpeechRecognizer(app)
        }

        val session = Listener(locale)
        listener = session
        recognizer = next
        next.setRecognitionListener(session)
        next.startListening(intent)
    }

    /**
     * One per session. Callbacks from a recognizer that has since been
     * replaced are dropped, so a late result can't leak into the next take.
     */
    private inner class Listener(private val locale: String) : RecognitionListener {
        private val current get() = listener === this

        private fun words(bundle: Bundle?) =
            bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: ""

        private fun send(words: String, isFinal: Boolean) {
            if (current) channel.invokeMethod("onWords", mapOf("words" to words, "final" to isFinal))
        }

        private fun end(idle: Boolean) {
            if (current) channel.invokeMethod("onSessionEnd", mapOf("idle" to idle))
        }

        override fun onPartialResults(partialResults: Bundle?) = send(words(partialResults), false)

        /** Continuous mode: one finished stretch of speech; listening goes on. */
        override fun onSegmentResults(segmentResults: Bundle) = send(words(segmentResults), true)

        override fun onEndOfSegmentedSession() = end(idle = true)

        /** Restart mode, or a recognizer that ignored the segmented request. */
        override fun onResults(results: Bundle?) {
            send(words(results), true)
            end(idle = false)
        }

        override fun onError(error: Int) {
            if (!current) return
            lastError = "${errorCode(error)} (${if (continuous) "continuous" else "restart"}, " +
                "${java.text.SimpleDateFormat("HH:mm:ss", Locale.US).format(java.util.Date())})"
            // The offline model turned out to be missing: carry on online.
            if (continuous && error in LANGUAGE_ERRORS) {
                onDeviceFailed.add(locale)
                continuous = false
                listen(locale)
                return
            }
            channel.invokeMethod("onError", mapOf("code" to errorCode(error)))
        }

        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun errorCode(error: Int) = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "error_audio_error"
        SpeechRecognizer.ERROR_CLIENT -> "error_client"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "error_permission"
        SpeechRecognizer.ERROR_NETWORK -> "error_network"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "error_network_timeout"
        SpeechRecognizer.ERROR_NO_MATCH -> "error_no_match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "error_busy"
        SpeechRecognizer.ERROR_SERVER -> "error_server"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "error_speech_timeout"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "error_language_not_supported"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "error_language_unavailable"
        SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "error_server_disconnected"
        SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "error_too_many_requests"
        else -> "error_unknown_$error"
    }
}
