import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:path_provider/path_provider.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:feedback/feedback.dart';

import '../utils/logger.dart';

class FeedbackService {
  static const _log = AppLogger('app.feedback');
  static const _supportEmail = 'support@example.com';

  /// Optional analytics callback fired when feedback is sent (or fails).
  static void Function()? onFeedbackSent;

  static Future<void> sendFeedback(UserFeedback feedback) async {
    if (kIsWeb) {
      // Platform channels and dart:io are unavailable on web. The feedback
      // button should be hidden in the web UI, but if it's triggered, log the
      // feedback text rather than crashing with an UnsupportedError.
      _log.info('Web feedback (not sent): ${feedback.text}');
      onFeedbackSent?.call();
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final screenshotPath = '${tempDir.path}/feedback_screenshot.png';
      final file = File(screenshotPath);
      await file.writeAsBytes(feedback.screenshot);

      final email = Email(
        body: feedback.text,
        subject: 'App Feedback',
        recipients: [_supportEmail],
        attachmentPaths: [screenshotPath],
      );

      await FlutterEmailSender.send(email);
      onFeedbackSent?.call();
    } catch (e, stack) {
      _log.error('Error sending feedback', error: e, stackTrace: stack);
    }
  }
}
