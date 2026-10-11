/// A file tracked in the Lite Reader library.
class LibraryDocument {
  const LibraryDocument({
    this.id,
    required this.uri,
    required this.source,
    required this.displayName,
    required this.mimeType,
    required this.size,
    required this.modified,
    this.pageCount = 0,
    this.thumbnailPath,
    this.starred = false,
    this.lastOpened = 0,
  });

  final int? id;
  /// SAF tree child URI, a content:// URI, or an app-private file path.
  final String uri;
  /// 'tree' (from an added SAF folder), 'external' (opened from outside),
  /// 'app' (created by Lite Reader tools).
  final String source;
  final String displayName;
  final String mimeType;
  final int size;
  final int modified;
  final int pageCount;
  final String? thumbnailPath;
  final bool starred;
  final int lastOpened;

  bool get isPdf => mimeType == 'application/pdf';

  LibraryDocument copyWith({
    int? id,
    String? uri,
    String? source,
    String? displayName,
    String? mimeType,
    int? size,
    int? modified,
    int? pageCount,
    String? thumbnailPath,
    bool? starred,
    int? lastOpened,
  }) {
    return LibraryDocument(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      source: source ?? this.source,
      displayName: displayName ?? this.displayName,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      pageCount: pageCount ?? this.pageCount,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      starred: starred ?? this.starred,
      lastOpened: lastOpened ?? this.lastOpened,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'uri': uri,
        'source': source,
        'display_name': displayName,
        'mime_type': mimeType,
        'size': size,
        'modified': modified,
        'page_count': pageCount,
        'thumbnail_path': thumbnailPath,
        'starred': starred ? 1 : 0,
        'last_opened': lastOpened,
      };

  factory LibraryDocument.fromMap(Map<String, Object?> map) {
    return LibraryDocument(
      id: map['id'] as int?,
      uri: map['uri'] as String,
      source: map['source'] as String? ?? 'tree',
      displayName: map['display_name'] as String? ?? '',
      mimeType: map['mime_type'] as String? ?? 'application/pdf',
      size: (map['size'] as num?)?.toInt() ?? 0,
      modified: (map['modified'] as num?)?.toInt() ?? 0,
      pageCount: (map['page_count'] as num?)?.toInt() ?? 0,
      thumbnailPath: map['thumbnail_path'] as String?,
      starred: (map['starred'] as num?)?.toInt() == 1,
      lastOpened: (map['last_opened'] as num?)?.toInt() ?? 0,
    );
  }
}
