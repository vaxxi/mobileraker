import 'dart:async';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:mobileraker/datasource/websocket_wrapper.dart';
import 'package:mobileraker/app/app_setup.logger.dart';
import 'package:mobileraker/dto/files/folder.dart';
import 'package:mobileraker/dto/files/gcode_file.dart';

enum FileRoot { gcodes, config, config_examples, docs }

enum FileAction {
  create_file,
  create_dir,
  delete_file,
  delete_dir,
  move_file,
  move_dir,
  modify_file,
  root_update
}

/// The FileService handles all file changes of the different roots of moonraker
/// For more information check out
/// 1. https://moonraker.readthedocs.io/en/latest/web_api/#file-operations
/// 2. https://moonraker.readthedocs.io/en/latest/web_api/#file-list-changed
class FileService {
  final WebSocketWrapper _webSocket;
  final _logger = getLogger('FileService');


  FileService(this._webSocket) {
    _webSocket.addMethodListener(_onFileListChanged, "notify_filelist_changed");

    // _webSocket.stateStream.listen((value) {
    //   switch (value) {
    //     case WebSocketState.connected:
    //       // _fetchAvailableFiles(FileRoot.gcodes);
    //
    //       // _fetchDirectoryInfo('gcodes', true);
    //       break;
    //     default:
    //   }
    // });
  }

  _onFileListChanged(Map<String, dynamic> rawMessage) {
    Map<String, dynamic> params = rawMessage['params'][0];
    FileAction? fileAction =
        EnumToString.fromString(FileAction.values, params['action']);
  }

  Future<FolderReqWrapper> fetchDirectoryInfo(String path,
      [bool extended = false]) async {
    Completer<FolderReqWrapper> reqCompleter = Completer();
    _logger.i('Fetching for `$path` [extended:$extended]');


    _webSocket.sendObject("server.files.get_directory",
        (response) => _parseDirectory(response, path, reqCompleter),
        params: {'path': path, 'extended': extended});
    return reqCompleter.future;
  }

  _fetchAvailableFiles(FileRoot root) {
    _webSocket.sendObject(
        "server.files.list", (response) => _parseResult(response, root),
        params: {'root': EnumToString.convertToString(root)});
  }


  Future<GCodeFile> getGCodeMetadata(String filename) async {
    Completer<GCodeFile> reqCompleter = Completer();
    _logger.i('Getting meta for file: `$filename`');


    _webSocket.sendObject("server.files.metadata",
            (response) => _parseFileMeta(response, filename, reqCompleter),
        params: {'filename': filename});
    return reqCompleter.future;
  }

  _parseResult(response, FileRoot root) {
    // List<dynamic> fileList = response; // Just add an type
    //
    // List<File> files = List.empty(growable: true);
    // for (var element in fileList) {
    //   String path = element['path'];
    //   double lastModified = element['modified'];
    //   int size = element['size'];
    //
    //   List<String> split = path.split('/');
    //   String fileName = split.removeLast();
    //
    //   for (var parents in split) {}
    // }
    //
    // fileStream.add(listOfGcodes);
  }

  _parseDirectory(
      response, String forPath, Completer<FolderReqWrapper> completer) {
    List<dynamic> filesResponse = response['files']; // Just add an type
    List<dynamic> directoriesResponse = response['dirs']; // Just add an type

    directoriesResponse.removeWhere((element) {
      String name = element['dirname'];
      return name.startsWith('.');
    });

    List<Folder> listOfFolder =
        List.generate(directoriesResponse.length, (index) {
      var element = directoriesResponse[index];
      String name = element['dirname'];
      double lastModified = element['modified'];
      int size = element['size'];

      return Folder(name: name, modified: lastModified, size: size);
    });

    filesResponse.removeWhere((element) {
      String name = element['filename'];
      return !name.toLowerCase().endsWith('gcode');
    });

    List<GCodeFile> listOfFiles = List.generate(filesResponse.length, (index) {
      var element = filesResponse[index];
      return GCodeFile.fromJson(element, forPath);
    });

    completer.complete(FolderReqWrapper(forPath,listOfFolder, listOfFiles));
  }

  _parseFileMeta(response, String forFile, Completer<GCodeFile> completer) {
    var split = forFile.split('/');
    split.removeLast();
    split.insert(0, 'gcodes');// we need to add the gcodes here since the getMetaInfo omits gcodes path.

    ;
    completer.complete(GCodeFile.fromJson(response, split.join('/')));
  }
}

class FolderReqWrapper {
  String reqPath;
  List<Folder> folders;
  List<GCodeFile> gCodes;

  FolderReqWrapper(this.reqPath, this.folders, this.gCodes);
}