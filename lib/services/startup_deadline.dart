import 'dart:async';

/// One shared budget for initialization, profile and authorization checks.
class StartupDeadline {
  StartupDeadline(Duration budget) : _endsAt = DateTime.now().add(budget);
  final DateTime _endsAt;

  Future<T> run<T>(Future<T> operation) {
    final remaining = _endsAt.difference(DateTime.now());
    return operation.timeout(remaining.isNegative ? Duration.zero : remaining);
  }
}
