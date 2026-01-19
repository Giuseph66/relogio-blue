/// Result type for error handling
/// Either contains a value of type T or an error of type E
sealed class Result<T, E> {
  const Result();
  
  /// Returns true if this is a success result
  bool get isSuccess => this is Success<T, E>;
  
  /// Returns true if this is a failure result
  bool get isFailure => this is Failure<T, E>;
  
  /// Gets the value if success, null otherwise
  T? get valueOrNull => switch (this) {
    Success(value: final v) => v,
    Failure() => null,
  };
  
  /// Gets the error if failure, null otherwise
  E? get errorOrNull => switch (this) {
    Success() => null,
    Failure(error: final e) => e,
  };
  
  /// Maps the value if success
  Result<U, E> map<U>(U Function(T) mapper) {
    return switch (this) {
      Success(value: final v) => Success(mapper(v)),
      Failure(error: final e) => Failure(e),
    };
  }
  
  /// Maps the error if failure
  Result<T, F> mapError<F>(F Function(E) mapper) {
    return switch (this) {
      Success(value: final v) => Success(v),
      Failure(error: final e) => Failure(mapper(e)),
    };
  }
  
  /// Executes a function if success
  Result<T, E> onSuccess(void Function(T) action) {
    if (this is Success<T, E>) {
      action((this as Success<T, E>).value);
    }
    return this;
  }
  
  /// Executes a function if failure
  Result<T, E> onFailure(void Function(E) action) {
    if (this is Failure<T, E>) {
      action((this as Failure<T, E>).error);
    }
    return this;
  }
}

/// Success result containing a value
final class Success<T, E> extends Result<T, E> {
  final T value;
  const Success(this.value);
  
  @override
  String toString() => 'Success($value)';
}

/// Failure result containing an error
final class Failure<T, E> extends Result<T, E> {
  final E error;
  const Failure(this.error);
  
  @override
  String toString() => 'Failure($error)';
}

