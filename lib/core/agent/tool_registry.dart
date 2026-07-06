import '../tools/confirm_tool.dart';
import '../tools/device_tools.dart';
import '../tools/schedule_tools.dart';
import '../tools/screen_tool.dart';
import '../tools/shell_tool.dart';
import '../tools/tool.dart';
import '../tools/ui_tool.dart';

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
      ScheduleNotificationTool(),
      CreateUiTool(),
      ScreenControlTool(),
      ConfirmTool(),
    ]);
  }

  void _register(List<Tool> tools) {
    for (final t in tools) {
      _tools[t.name] = t;
    }
  }

  Tool? byName(String name) => _tools[name];

  List<Map<String, dynamic>> get declarations =>
      _tools.values.map((t) => t.toDeclaration()).toList();
}
