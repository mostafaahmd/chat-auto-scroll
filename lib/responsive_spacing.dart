// A utility class that provides responsive spacing values for various UI elements in a chat application. The spacing values are calculated based on the available width, allowing the UI to adapt to different screen sizes while maintaining a consistent look and feel. The class includes methods for calculating horizontal and vertical padding for the chat composer and messages, as well as a method for calculating the maximum width of the composer. The spacing values are clamped to ensure they stay within reasonable limits, preventing excessive padding on larger screens or insufficient padding on smaller screens.
import 'dart:math' as math;

/// A utility class that provides responsive spacing values for various UI elements in a chat application.
class ResponsiveSpacing {
  const ResponsiveSpacing._();

  /// Returns the horizontal padding value for the chat composer based on the available width.
  static double composerHorizontalPadding(double availableWidth) {
    return _clamp(availableWidth * 0.018, min: 10, max: 24);
  }

  /// Returns the vertical padding value for the chat composer based on the available width.
  static double composerVerticalPadding(double availableWidth) {
    return _clamp(availableWidth * 0.008, min: 8, max: 14);
  }
  /// Returns the horizontal padding value for individual chat messages based on the available width.
  static double messageHorizontalPadding(double availableWidth) {
    return _clamp(availableWidth * 0.014, min: 10, max: 18);
  }
  
  /// Returns the vertical padding value for individual chat messages based on the available width.
  static double messageVerticalPadding(double availableWidth) {
    return _clamp(availableWidth * 0.008, min: 8, max: 14);
  }

  /// Returns the gap value between UI elements based on the available width.
  static double gap(double availableWidth) {
    return _clamp(availableWidth * 0.008, min: 6, max: 12);
  }
  
  /// Returns the maximum width value for the chat composer based on the available width.
  static double composerMaxWidth(double availableWidth) {
    if (availableWidth < 720) return availableWidth;
    return math.min(availableWidth * 0.86, 1100);
  }
  
  /// A helper method to clamp a value between a minimum and maximum range. This is used to ensure that the calculated spacing values do not exceed reasonable limits, providing a consistent user experience across different screen sizes.
  static double _clamp(
    double value, {
    required double min,
    required double max,
  }) {
    return value.clamp(min, max);
  }
}