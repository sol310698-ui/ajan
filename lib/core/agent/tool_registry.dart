import '../tools/device_tools.dart';
import '../tools/shell_tool.dart';
import '../tools/tool.dart';

/// Tum araclarin kayit merkezi. Yeni yetenek eklemek = buraya bir satir.
class ToolRegistry {
  final Map<String, Tool> _tools = {};

  ToolRegistry() {
    _register([
      ShellTool(),
      OpenAppTool(),
      SendSmsTool(),
      LocationTool(),
      NotifyTool(),
    ]);
  }

  void _register(List<Tool> tools) {
    for (final t in tools) {
      _tools[t.name] = t;
    }
  }

  Tool? byName(String name) => _tools[name];

  /// Gemini'ye gonderilecek functionDeclarations listesi.
  List<Map<String, dynamic>> get declarations =>
      _tools.values.map((t) => t.toDeclaration()).toList();
}
