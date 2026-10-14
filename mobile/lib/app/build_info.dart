class BuildInfo {
  static const version =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.2.5');
  static const builtAt =
      String.fromEnvironment('BUILD_TIME', defaultValue: '本地开发版');
}
