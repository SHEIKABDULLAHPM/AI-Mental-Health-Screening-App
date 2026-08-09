/// Form validation helpers shared across auth & screening screens.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static String? required(String? value,
      [String message = 'This field is required',]) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  static String? email(String? value) {
    final empty = required(value);
    if (empty != null) return empty;
    if (!_email.hasMatch(value!.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? password(String? value, {bool allowWeak = false}) {
    final empty = required(value);
    if (empty != null) return empty;
    if (value!.length < 8) return 'Use at least 8 characters';
    if (!allowWeak) {
      if (!RegExp(r'[A-Z]').hasMatch(value)) {
        return 'Include at least one capital letter';
      }
      if (!RegExp(r'[0-9]').hasMatch(value)) {
        return 'Include at least one number';
      }
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }

  static String? age(String? value) {
    final empty = required(value);
    if (empty != null) return empty;
    final n = int.tryParse(value!);
    if (n == null || n < 13 || n > 120) return 'Enter a valid age (13+)';
    return null;
  }
}
