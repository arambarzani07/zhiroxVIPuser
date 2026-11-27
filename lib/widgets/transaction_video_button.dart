import 'package:flutter/material.dart';

/// Transaction video capture and playback are disabled in the User edition.
/// Keep the existing call-site contract without exposing video controls.
class TransactionVideoButton extends StatelessWidget {
  const TransactionVideoButton({
    super.key,
    required this.sourceType,
    required this.sourceId,
  });

  final String sourceType;
  final String sourceId;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
