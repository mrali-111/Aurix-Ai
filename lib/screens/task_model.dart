class TaskModel {
  final int id;
  final String name;
  final String time;
  DateTime taskDateTime;  // 👈 "final" hatao
  bool isDone;
  String? doneAt;

  TaskModel({
    required this.id,
    required this.name,
    required this.time,
    required this.taskDateTime,  // 👈 required
    this.isDone = false,
    this.doneAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'time': time,
    'taskDateTime': taskDateTime.toIso8601String(),
    'isDone': isDone,
    'doneAt': doneAt,
  };

  factory TaskModel.fromJson(Map<String, dynamic> json) => TaskModel(
    id: json['id'],
    name: json['name'],
    time: json['time'],
    taskDateTime: DateTime.parse(json['taskDateTime']),
    isDone: json['isDone'] ?? false,
    doneAt: json['doneAt'],
  );
}