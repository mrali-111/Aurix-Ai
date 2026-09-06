import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:aurix_ai/screens/task_model.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

class ReminderScreen extends StatefulWidget {
  final Function(List<TaskModel>) onTasksChanged;
  const ReminderScreen({super.key, required this.onTasksChanged});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen>
    with WidgetsBindingObserver {
  List<TaskModel> tasks = [];
  List<TaskModel> history = [];
  final _nameCtrl = TextEditingController();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
    _requestPermissions();
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
      _rescheduleAllNotifications();
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    await Permission.scheduleExactAlarm.request();
    await Permission.ignoreBatteryOptimizations.request();
  }



  void _openAutoStartSettings() {
    try {
      const intent = AndroidIntent(
        action: 'miui.intent.action.APP_PERM_EDITOR',
        arguments: {'extra_pkgname': 'com.example.aurix_ai'},
      );
      intent.launch();
    } catch (_) {
      try {
        openAppSettings();
      } catch (e) {
        debugPrint('Cannot open settings: $e');
      }
    }
  }

  Future<void> _initNotifications() async {
    tz.initializeTimeZones();

    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (details) {},
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  Future<void> _scheduleNotification(TaskModel task) async {
    final now = DateTime.now();
    var scheduleDate = DateTime(
      now.year,
      now.month,
      now.day,
      task.taskDateTime.hour,
      task.taskDateTime.minute,
    );

    if (scheduleDate.isBefore(now)) {
      scheduleDate = scheduleDate.add(const Duration(days: 1));
    }

    task.taskDateTime = scheduleDate;

    final tz.TZDateTime scheduledTZ =
    tz.TZDateTime.from(scheduleDate, tz.local);

    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Task Reminders',
      channelDescription: 'Notifications for your tasks',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      usesChronometer: true,
      ongoing: false,
      autoCancel: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task.id.hashCode,
      '⏰ Task Reminder',
      task.name,
      scheduledTZ,
      const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id.hashCode);
  }

  Future<void> _rescheduleAllNotifications() async {
    for (final task in tasks) {
      await _scheduleNotification(task);
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final tRaw = prefs.getStringList('tasks') ?? [];
    final hRaw = prefs.getStringList('history') ?? [];
    setState(() {
      tasks = tRaw.map((e) => TaskModel.fromJson(jsonDecode(e))).toList();
      history = hRaw.map((e) => TaskModel.fromJson(jsonDecode(e))).toList();
    });
    widget.onTasksChanged(tasks);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'tasks', tasks.map((e) => jsonEncode(e.toJson())).toList());
    await prefs.setStringList(
        'history', history.map((e) => jsonEncode(e.toJson())).toList());
    widget.onTasksChanged(tasks);
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A1A1A), onSurface: Color(0xFF1A1A1A)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  void _addTask() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('⚠️ Task naam likhein!'),
            backgroundColor: Color(0xFF1A1A1A)),
      );
      return;
    }
    final now = DateTime.now();
    var dt = DateTime(
        now.year, now.month, now.day, _selectedTime.hour, _selectedTime.minute);
    if (dt.isBefore(now)) dt = dt.add(const Duration(days: 1));

    final task = TaskModel(
      id: DateTime.now().millisecondsSinceEpoch,
      name: name,
      time: _fmtTime(_selectedTime),
      taskDateTime: dt,
    );

    setState(() {
      tasks.add(task);
      tasks.sort((a, b) => a.taskDateTime.compareTo(b.taskDateTime));
    });
    _nameCtrl.clear();
    _scheduleNotification(task);
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('✅ Task added with reminder!'),
          backgroundColor: Color(0xFF1A1A1A)),
    );
  }

  void _markDone(TaskModel t) {
    _cancelNotification(t.id);
    setState(() {
      tasks.remove(t);
      t.isDone = true;
      t.doneAt = TimeOfDay.now().format(context);
      history.insert(0, t);
      if (history.length > 30) history = history.sublist(0, 30);
    });
    _saveData();
  }

  void _deleteTask(TaskModel t) {
    _cancelNotification(t.id);
    setState(() => tasks.remove(t));
    _saveData();
  }

  void _deleteHistory(TaskModel t) {
    setState(() => history.remove(t));
    _saveData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F0ED),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.9), width: 1.5),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: 16, color: Color(0xFF1A1A1A)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text('Reminder',
                      style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 24,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.9), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Add Task',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: 0.3)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        hintText: 'Task name',
                        hintStyle: const TextStyle(
                            color: Color(0xFFAAAAAA), fontSize: 13),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.7),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.8))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.8))),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF7C4DFF), width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                      ),
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF1A1A1A)),
                      onSubmitted: (_) async {
                        await _requestPermissions();
                        _addTask();
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickTime,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.8)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 16, color: Color(0xFF888888)),
                                  const SizedBox(width: 8),
                                  Text(_fmtTime(_selectedTime),
                                      style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF1A1A1A),
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () async {
                            await _requestPermissions();
                            _addTask();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('+ Add',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.9))),
                child: Row(
                  children: [
                    _tab(0, '🔔 Active (${tasks.length})'),
                    _tab(1, '📋 History (${history.length})'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
                child: _tabIndex == 0 ? _buildActiveList() : _buildHistoryList()),
          ],
        ),
      ),
    );
  }

  Widget _tab(int idx, String label) {
    final active = _tabIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1A1A1A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : const Color(0xFF999999),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveList() {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm_off_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text('Not Active Task.\nAdd Now!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: tasks.length,
      itemBuilder: (ctx, i) {
        final t = tasks[i];
        return Dismissible(
          key: Key('t${t.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          onDismissed: (_) => _deleteTask(t),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _activeTaskCard(t),
          ),
        );
      },
    );
  }

  Widget _activeTaskCard(TaskModel t) {
    final diff = t.taskDateTime.difference(DateTime.now());
    final isOverdue = diff.isNegative;
    final mins = diff.inMinutes;
    Color barColor = mins < 10
        ? Colors.red
        : mins < 60
        ? Colors.orange
        : Colors.green;
    String timeLeft = isOverdue
        ? 'Waqt aa gaya!'
        : diff.inHours > 0
        ? '${diff.inHours}h ${diff.inMinutes % 60}m'
        : '${diff.inMinutes}m ${diff.inSeconds % 60}s';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.9), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text('⏰ ${t.time} time',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF888888))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(timeLeft,
                      style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isOverdue ? Colors.red : barColor)),
                  const SizedBox(height: 2),
                  const Text('Task Remaining',
                      style: TextStyle(fontSize: 9, color: Color(0xFFAAAAAA))),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _actionBtn('✓ Done', const Color(0xFFE8F5E9),
                          const Color(0xFF4CAF50), () => _markDone(t)),
                      const SizedBox(width: 6),
                      _actionBtn('✕', const Color(0xFFFFEBEE),
                          Colors.red, () => _deleteTask(t)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isOverdue
                  ? 1.0
                  : 1.0 -
                  (diff.inSeconds /
                      const Duration(hours: 24).inSeconds),
              backgroundColor: Colors.black.withOpacity(0.06),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text('Koi history nahi abhi.',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: history.length,
      itemBuilder: (ctx, i) {
        final t = history[i];
        return Dismissible(
          key: Key('h${t.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          onDismissed: (_) => _deleteHistory(t),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withOpacity(0.8), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline,
                        color: Color(0xFF4CAF50), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF888888),
                                decoration: TextDecoration.lineThrough),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                            '⏰ ${t.time} baje${t.doneAt != null ? "  ·  Done: ${t.doneAt}" : ""}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFFAAAAAA))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('✓ Done',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4CAF50))),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionBtn(
      String label, Color bg, Color fg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ),
      );
}