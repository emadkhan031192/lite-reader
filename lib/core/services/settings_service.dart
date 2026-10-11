import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PageColorMode { paper, softGrey, night }

enum PageFlow { vertical, single }

enum DefaultZoom { fitWidth, fitPage, hundred }

enum OpenLocationMode { lastUsed, chosen }

/// All user settings. Persisted in SharedPreferences, exposed via Riverpod.
class SettingsState {
  const SettingsState({
    this.pageColor = PageColorMode.paper,
    this.followSystemTheme = true,
    this.pageFlow = PageFlow.vertical,
    this.defaultZoom = DefaultZoom.fitWidth,
    this.rememberLastPage = true,
    this.tapEdgesToTurnPages = true,
    this.volumeKeysTurnPages = false,
    this.keepScreenAwake = false,
    this.showFileExtensions = true,
    this.openLocationMode = OpenLocationMode.lastUsed,
    this.chosenFolderUri,
    this.lastUsedFolderUri,
  });

  final PageColorMode pageColor;
  final bool followSystemTheme;
  final PageFlow pageFlow;
  final DefaultZoom defaultZoom;
  final bool rememberLastPage;
  final bool tapEdgesToTurnPages;
  final bool volumeKeysTurnPages;
  final bool keepScreenAwake;
  final bool showFileExtensions;
  final OpenLocationMode openLocationMode;
  final String? chosenFolderUri;
  final String? lastUsedFolderUri;

  SettingsState copyWith({
    PageColorMode? pageColor,
    bool? followSystemTheme,
    PageFlow? pageFlow,
    DefaultZoom? defaultZoom,
    bool? rememberLastPage,
    bool? tapEdgesToTurnPages,
    bool? volumeKeysTurnPages,
    bool? keepScreenAwake,
    bool? showFileExtensions,
    OpenLocationMode? openLocationMode,
    String? chosenFolderUri,
    String? lastUsedFolderUri,
  }) {
    return SettingsState(
      pageColor: pageColor ?? this.pageColor,
      followSystemTheme: followSystemTheme ?? this.followSystemTheme,
      pageFlow: pageFlow ?? this.pageFlow,
      defaultZoom: defaultZoom ?? this.defaultZoom,
      rememberLastPage: rememberLastPage ?? this.rememberLastPage,
      tapEdgesToTurnPages: tapEdgesToTurnPages ?? this.tapEdgesToTurnPages,
      volumeKeysTurnPages: volumeKeysTurnPages ?? this.volumeKeysTurnPages,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
      showFileExtensions: showFileExtensions ?? this.showFileExtensions,
      openLocationMode: openLocationMode ?? this.openLocationMode,
      chosenFolderUri: chosenFolderUri ?? this.chosenFolderUri,
      lastUsedFolderUri: lastUsedFolderUri ?? this.lastUsedFolderUri,
    );
  }
}

class SettingsController extends Notifier<SettingsState> {
  static const _kPageColor = 'page_color';
  static const _kFollowSystem = 'follow_system_theme';
  static const _kPageFlow = 'page_flow';
  static const _kDefaultZoom = 'default_zoom';
  static const _kRememberLastPage = 'remember_last_page';
  static const _kTapEdges = 'tap_edges_turn_pages';
  static const _kVolumeKeys = 'volume_keys_turn_pages';
  static const _kKeepAwake = 'keep_screen_awake';
  static const _kShowExtensions = 'show_file_extensions';
  static const _kOpenLocationMode = 'open_location_mode';
  static const _kChosenFolder = 'chosen_folder_uri';
  static const _kLastUsedFolder = 'last_used_folder_uri';

  SharedPreferences? _prefs;

  @override
  SettingsState build() {
    _load();
    return const SettingsState();
  }

  Future<void> _load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    state = SettingsState(
      pageColor: PageColorMode.values[p.getInt(_kPageColor) ?? 0],
      followSystemTheme: p.getBool(_kFollowSystem) ?? true,
      pageFlow: PageFlow.values[p.getInt(_kPageFlow) ?? 0],
      defaultZoom: DefaultZoom.values[p.getInt(_kDefaultZoom) ?? 0],
      rememberLastPage: p.getBool(_kRememberLastPage) ?? true,
      tapEdgesToTurnPages: p.getBool(_kTapEdges) ?? true,
      volumeKeysTurnPages: p.getBool(_kVolumeKeys) ?? false,
      keepScreenAwake: p.getBool(_kKeepAwake) ?? false,
      showFileExtensions: p.getBool(_kShowExtensions) ?? true,
      openLocationMode: OpenLocationMode.values[p.getInt(_kOpenLocationMode) ?? 0],
      chosenFolderUri: p.getString(_kChosenFolder),
      lastUsedFolderUri: p.getString(_kLastUsedFolder),
    );
  }

  Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    final s = state;
    await p.setInt(_kPageColor, s.pageColor.index);
    await p.setBool(_kFollowSystem, s.followSystemTheme);
    await p.setInt(_kPageFlow, s.pageFlow.index);
    await p.setInt(_kDefaultZoom, s.defaultZoom.index);
    await p.setBool(_kRememberLastPage, s.rememberLastPage);
    await p.setBool(_kTapEdges, s.tapEdgesToTurnPages);
    await p.setBool(_kVolumeKeys, s.volumeKeysTurnPages);
    await p.setBool(_kKeepAwake, s.keepScreenAwake);
    await p.setBool(_kShowExtensions, s.showFileExtensions);
    await p.setInt(_kOpenLocationMode, s.openLocationMode.index);
    if (s.chosenFolderUri != null) {
      await p.setString(_kChosenFolder, s.chosenFolderUri!);
    }
    if (s.lastUsedFolderUri != null) {
      await p.setString(_kLastUsedFolder, s.lastUsedFolderUri!);
    }
  }

  Future<void> update(SettingsState Function(SettingsState) fn) async {
    state = fn(state);
    await _save();
  }

  Future<void> noteFolderUsed(String treeUri) async {
    await update((s) => s.copyWith(lastUsedFolderUri: treeUri));
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
