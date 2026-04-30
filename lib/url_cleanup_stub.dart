/// Non-web stub. The conditional import in main.dart only resolves to
/// the real implementation under `dart.library.js_interop` (web), so
/// every native build sees this no-op and never pulls in
/// `package:web` (which references `dart:js_interop` types that don't
/// exist on the Android / iOS / desktop compilers and break the
/// kernel build).
void replaceUrl(String cleanedUrl) {}
