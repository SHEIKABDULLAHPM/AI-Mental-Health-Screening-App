/// Transient state shared across the forgot-password screens.
///
/// The reset token is a single-use, server-issued secret, only ever held in
/// memory for the duration of this flow.
class ForgotFlow {
  ForgotFlow._();

  static String email = '';
  static String resetToken = '';

  static void reset() {
    email = '';
    resetToken = '';
  }
}
