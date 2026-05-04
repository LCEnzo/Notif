import 'dart:math';

String? validateEmail(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter an email address';
  }

  if (!RegExp(
    r'^[a-zA-Z0-9.+\-]+@[a-zA-Z0-9\-]+(\.[a-zA-Z0-9\-]+)*\.[a-zA-Z]{2,}$',
  ).hasMatch(value)) {
    return 'Please enter a valid email address';
  }

  return null;
}

class EntropyValidator {
  const EntropyValidator();

  static const double timeInSeconds =
      100 * 365 * 24 * 60 * 60; // 100 years in seconds
  static const double attemptsPerSecond =
      1e9; // Estimated attempts per second for a consumer CPU
  static final double minEntropy = log(timeInSeconds * attemptsPerSecond) / ln2;

  String? validate(String? password) {
    if (password == null || password.isEmpty) {
      return "Password cannot be empty";
    }

    double passwordEntropy = calculatePasswordEntropy(password);
    if (passwordEntropy < minEntropy) {
      return getHelpText(passwordEntropy: passwordEntropy);
    }

    return null;
  }

  String getHelpText({double? passwordEntropy}) {
    // ignore: prefer_interpolation_to_compose_strings
    return 'Use more and different characters. "S0m3 password!"';
  }

  double calculatePasswordEntropy(String password) {
    final hasDigit = password.contains(RegExp(r'\d'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasPunct = password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'));
    final hasOther = password.contains(RegExp(r'[^\w\s]'));

    List<bool> categories = [hasDigit, hasLower, hasUpper, hasPunct, hasOther];
    List<int> lengths = [10, 26, 26, 32, 40];
    int charSet = 0;

    for (var index = 0; index < categories.length; index++) {
      if (categories[index]) {
        charSet += lengths[index];
      }
    }

    if (charSet == 0) {
      return 0; // No valid characters, so entropy is zero
    }

    return log(charSet) / ln2 * password.length;
  }
}
