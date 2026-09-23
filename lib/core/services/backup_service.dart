import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class BackupService {
  /// Resolves a safe directory for Habit Loop backups.
  /// Uses public Download/Documents storage on Android, or app documents directory as fallback.
  Future<Directory> _getHabitLoopBackupDirectory() async {
    Directory? targetDir;

    if (Platform.isAndroid) {
      try {
        final downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          targetDir = Directory('${downloadDir.path}${Platform.pathSeparator}Habit Loop${Platform.pathSeparator}Backup');
        }
      } catch (_) {}

      if (targetDir == null) {
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            targetDir = Directory('${extDir.path}${Platform.pathSeparator}Habit Loop${Platform.pathSeparator}Backup');
          }
        } catch (_) {}
      }

      targetDir ??= Directory('/storage/emulated/0/Download/Habit Loop/Backup');
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final baseDir = (await getDownloadsDirectory()) ?? (await getApplicationDocumentsDirectory());
      targetDir = Directory('${baseDir.path}${Platform.pathSeparator}Habit Loop${Platform.pathSeparator}Backup');
    } else {
      final baseDir = await getApplicationDocumentsDirectory();
      targetDir = Directory('${baseDir.path}${Platform.pathSeparator}Habit Loop${Platform.pathSeparator}Backup');
    }

    try {
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      return targetDir;
    } catch (_) {
      final fallback = await getApplicationDocumentsDirectory();
      final fallbackDir = Directory('${fallback.path}${Platform.pathSeparator}Habit Loop${Platform.pathSeparator}Backup');
      if (!fallbackDir.existsSync()) {
        await fallbackDir.create(recursive: true);
      }
      return fallbackDir;
    }
  }

  /// Saves [jsonString] directly into a .json backup file.
  /// Uses system file picker dialog on Android/Desktop or fallback backup folder.
  Future<String?> saveJsonToDownloads(String jsonString) async {
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'habit_loop_backup_$timestamp.json';
    final bytes = Uint8List.fromList(utf8.encode(jsonString));

    // 1. Try file picker save dialog first (Storage Access Framework on Android)
    try {
      final saveResult = await FilePickerPlatform.instance.saveFile(
        dialogTitle: 'Save Habit Backup JSON',
        fileName: fileName,
        bytes: bytes,
        mimeType: 'application/json',
      );

      if (saveResult != null) {
        final savePath = saveResult.toString();
        if (savePath.isNotEmpty) {
          final file = File(savePath);
          await file.writeAsString(jsonString);
          return savePath;
        }
      }
    } catch (_) {
      // Fallback to direct directory write if saveFile dialog is unavailable
    }

    // 2. Direct file write to backup folder
    final backupDir = await _getHabitLoopBackupDirectory();
    final filePath = '${backupDir.path}${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    await file.writeAsString(jsonString);
    return filePath;
  }

  /// Scans the default Habit Loop backup directory and returns any existing backup .json files.
  Future<List<File>> getAvailableBackupFiles() async {
    final backupFiles = <File>[];
    try {
      final dir = await _getHabitLoopBackupDirectory();
      if (dir.existsSync()) {
        final list = dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.json')).toList();
        list.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        backupFiles.addAll(list);
      }
    } catch (_) {}

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        final backupDir = Directory('${downloadsDir.path}${Platform.pathSeparator}Habit Loop${Platform.pathSeparator}Backup');
        if (backupDir.existsSync()) {
          final list = backupDir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.json')).toList();
          for (final f in list) {
            if (!backupFiles.any((existing) => existing.path == f.path)) {
              backupFiles.add(f);
            }
          }
        }
      }
    } catch (_) {}

    return backupFiles;
  }

  /// Reads contents from a specific [File].
  Future<String?> readJsonFromFile(File file) async {
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Opens file manager picker to let user pick and restore any backup file.
  /// Uses FileType.any to ensure Android file picker does not gray out .json files.
  Future<String?> pickAndReadJsonFile() async {
    Directory? backupDir;
    try {
      backupDir = await _getHabitLoopBackupDirectory();
    } catch (_) {}

    final files = await FilePickerPlatform.instance.pickFiles(
      type: FileType.any,
      initialDirectory: backupDir?.path,
    );

    if (files.isEmpty) {
      return null;
    }

    final pickedFile = files.first;
    if (pickedFile.path != null && pickedFile.path!.isNotEmpty) {
      final file = File(pickedFile.path!);
      return await file.readAsString();
    }

    return null;
  }
}
