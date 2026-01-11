package com.example.fyp_app

import android.telephony.SmsManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.fyp_app/sms"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "sendSMS") {
                val number = call.argument<String>("number")
                val message = call.argument<String>("message")
                if (number != null && message != null) {
                    sendSMS(number, message, result)
                } else {
                    result.error("INVALID_ARGS", "Number or message missing", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun sendSMS(phoneNumber: String, message: String, result: MethodChannel.Result) {
        try {
            val smsManager = SmsManager.getDefault()
            smsManager.sendTextMessage(phoneNumber, null, message, null, null)
            result.success("SMS Sent")
        } catch (e: Exception) {
            result.error("SMS_FAILED", "Failed to send SMS: ${e.localizedMessage}", null)
        }
    }
}
