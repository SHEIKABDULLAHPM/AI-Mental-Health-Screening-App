class Validators {
  Validators._();

  static String? required(String? value, {String field = 'This field'}) {
    if ((value ?? '').trim().isEmpty) return '$field is required';
    return null;
  }

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email address is required';
    final regex = RegExp(r'^[\w\.\-\+]+@[\w\-]+(\.[\w\-]+)+$');
    if (!regex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? fullName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Full name is required';
    if (v.split(RegExp(r'\s+')).length < 2) {
      return 'Enter your first and last name';
    }
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) {
      return 'Include at least one uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Include at least one number';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please confirm your password';
    if (v != password) return 'Passwords do not match';
    return null;
  }

  static ({bool length, bool uppercase, bool number, bool symbol})
  passwordStrength(String value) {
    return (
      length: value.length >= 8,
      uppercase: RegExp(r'[A-Z]').hasMatch(value),
      number: RegExp(r'[0-9]').hasMatch(value),
      symbol: RegExp(r'[^A-Za-z0-9]').hasMatch(value),
    );
  }

  static String? age(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Age is required';
    final n = int.tryParse(v);
    if (n == null || n < 10 || n > 110) return 'Enter a valid age (10-110)';
    return null;
  }
}
