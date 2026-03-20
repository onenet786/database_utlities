class OperationResult {
  const OperationResult({
    required this.success,
    required this.message,
    required this.command,
  });

  final bool success;
  final String message;
  final String command;
}
