import 'browser_suite_stub.dart'
    if (dart.library.js_interop) 'browser_suite_web.dart' as suite;

void main() => suite.runBrowserSuite();
