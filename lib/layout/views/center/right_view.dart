import 'package:flutter/widgets.dart';

import '../../../features/ai/widgets/ai_chat_view.dart';

/// The right pane. Its whole job is the AI assistant; see [AiChatView].
class RightView extends StatelessWidget {
  const RightView({super.key});

  @override
  Widget build(BuildContext context) => const AiChatView();
}
