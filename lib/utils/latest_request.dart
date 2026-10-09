/// Prevents an older asynchronous response from replacing a newer selection.
class LatestRequest {
  int _generation = 0;

  int begin() => ++_generation;

  bool isCurrent(int generation) => generation == _generation;

  void invalidate() => ++_generation;
}
