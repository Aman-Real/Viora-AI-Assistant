import 'dart:typed_data';

enum Sender { user, assistant }

enum ConversationMode { chat, voice }

var _idSeq = 0;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_idSeq++).toRadixString(36)}';

class ChatMessage {
  ChatMessage({
    required this.sender,
    this.text = '',
    String? id,
    DateTime? time,
    this.image,
    bool? hadImage,
    List<String>? toolNotes,
    this.isError = false,
    this.isStreaming = false,
  })  : id = id ?? newId(),
        time = time ?? DateTime.now(),
        hadImage = hadImage ?? image != null,
        toolNotes = toolNotes ?? [];

  final String id;
  final Sender sender;
  final DateTime time;

  /// Kept in memory only; history stores [hadImage] instead of the bytes.
  final Uint8List? image;
  final bool hadImage;
  final List<String> toolNotes;
  String text;
  bool isError;
  bool isStreaming;

  bool get fromUser => sender == Sender.user;

  Map<String, Object?> toJson() => {
        'id': id,
        'sender': sender.name,
        'text': text,
        'time': time.toIso8601String(),
        if (hadImage) 'hadImage': true,
        if (toolNotes.isNotEmpty) 'tools': toolNotes,
        if (isError) 'error': true,
      };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
        id: json['id'] as String?,
        sender: Sender.values.byName(json['sender'] as String),
        text: json['text'] as String? ?? '',
        time: DateTime.tryParse(json['time'] as String? ?? ''),
        hadImage: json['hadImage'] == true,
        toolNotes: (json['tools'] as List<Object?>?)?.cast<String>().toList(),
        isError: json['error'] == true,
      );
}

class Conversation {
  Conversation({
    String? id,
    this.mode = ConversationMode.chat,
    this.title = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  final String id;
  final ConversationMode mode;
  final DateTime createdAt;
  DateTime updatedAt;
  String title;
  final List<ChatMessage> messages;

  String get displayTitle {
    if (title.isNotEmpty) return title;
    final first = messages.where((m) => m.fromUser && m.text.isNotEmpty).firstOrNull;
    return first == null ? 'New conversation' : titleFrom(first.text);
  }

  String get preview {
    final last = messages.where((m) => m.text.isNotEmpty).lastOrNull;
    return last == null ? '' : plain(last.text);
  }

  /// Markdown-free single line, for titles and previews.
  static String plain(String text) => text
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'^\s*[-•]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String titleFrom(String text) {
    final clean = plain(text);
    return clean.length <= 42 ? clean : '${clean.substring(0, 40).trimRight()}…';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'mode': mode.name,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.where((m) => !m.isStreaming).map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, Object?> json) => Conversation(
        id: json['id'] as String?,
        mode: ConversationMode.values.byName(json['mode'] as String? ?? 'chat'),
        title: json['title'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        messages: (json['messages'] as List<Object?>? ?? [])
            .map((m) => ChatMessage.fromJson((m as Map).cast<String, Object?>()))
            .toList(),
      );
}

class Reminder {
  Reminder({required this.id, required this.message, required this.when, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();

  final int id;
  final String message;
  final DateTime when;
  final DateTime createdAt;

  bool isPast(DateTime now) => !when.isAfter(now);

  Map<String, Object?> toJson() => {
        'id': id,
        'message': message,
        'when': when.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, Object?> json) => Reminder(
        id: json['id'] as int,
        message: json['message'] as String,
        when: DateTime.parse(json['when'] as String),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );
}
