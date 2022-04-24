import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:mobileraker/app/app_setup.locator.dart';
import 'package:mobileraker/app/app_setup.logger.dart';
import 'package:mobileraker/app/app_setup.router.dart';
import 'package:mobileraker/datasource/json_rpc_client.dart';
import 'package:mobileraker/domain/hive/machine.dart';
import 'package:mobileraker/dto/files/file.dart';
import 'package:mobileraker/dto/files/folder.dart';
import 'package:mobileraker/dto/files/gcode_file.dart';
import 'package:mobileraker/dto/files/notification/file_list_changed_item.dart';
import 'package:mobileraker/dto/files/notification/file_list_changed_notification.dart';
import 'package:mobileraker/dto/files/notification/file_list_changed_source_item.dart';
import 'package:mobileraker/dto/server/klipper.dart';
import 'package:mobileraker/service/moonraker/file_service.dart';
import 'package:mobileraker/service/moonraker/klippy_service.dart';
import 'package:mobileraker/service/machine_service.dart';
import 'package:mobileraker/service/selected_machine_service.dart';
import 'package:mobileraker/ui/components/dialog/renameFile/rename_file_dialog_view.dart';
import 'package:mobileraker/ui/components/dialog/setup_dialog_ui.dart';
import 'package:mobileraker/ui/components/snackbar/setup_snackbar.dart';
import 'package:mobileraker/util/path_utils.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

const String _SelectedPrinterStreamKey = 'selectedPrinter';
const String _FolderContentStreamKey = 'folderContent';
const String _FileNotification = 'fileNotification';
const String _ServerStreamKey = 'server';

class FilesViewModel extends MultipleStreamViewModel {
  final _logger = getLogger('FilesViewModel');

  final _dialogService = locator<DialogService>();
  final _navigationService = locator<NavigationService>();
  final _bottomSheetService = locator<BottomSheetService>();
  final _selectedMachineService = locator<SelectedMachineService>();
  final _snackBarService = locator<SnackbarService>();

  bool isSearching = false;

  int bottomNavIndex = 0;

  int selectedSorting = 0;

  List<Comparator<Folder>?> folderComparators = [
    (folderA, folderB) => folderB.modified.compareTo(folderA.modified),
    (folderA, folderB) => folderA.name.compareTo(folderB.name),
    null,
  ];

  late List<Comparator<File>?> fileComparators = [
    comperatorModified,
    comperatorName,
    comperatorPrintStart
  ];

  Machine? _machine;

  FileService? get _fileService => _machine?.fileService;

  KlippyService? get _klippyService => _machine?.klippyService;

  RefreshController refreshController =
      RefreshController(initialRefresh: false);

  TextEditingController searchEditingController = TextEditingController();

  StreamController<FolderContentWrapper> _folderContentStreamController =
      BehaviorSubject<FolderContentWrapper>();

  List<String> requestedPath = [];

  String get requestedPathAsString => requestedPath.join('/');

  Map<int, List<String>> lastPaths = {};

  @override
  Map<String, StreamData> get streamsMap => {
        _SelectedPrinterStreamKey:
            StreamData<Machine?>(_selectedMachineService.selectedMachine),
        if (_fileService != null) ...{
          _FolderContentStreamKey: StreamData<FolderContentWrapper>(
              _folderContentStreamController.stream),
          _FileNotification: StreamData<FileListChangedNotification>(
              _fileService!.fileNotificationStream)
        },
        if (_klippyService != null) ...{
          _ServerStreamKey:
              StreamData<KlipperInstance>(_klippyService!.klipperStream)
        }
      };

  @override
  onData(String key, data) {
    super.onData(key, data);
    switch (key) {
      case _SelectedPrinterStreamKey:
        Machine? nmachine = data;
        if (nmachine == _machine) break;
        _machine = nmachine;
        _fetchDirectoryData();
        notifySourceChanged(clearOldData: true);
        break;
      case _FileNotification:
        handleFileListChanged(data);
        break;

      default:
        break;
    }
  }

  onBottomItemTapped(int index) {
    if (index == bottomNavIndex) return;

    if (requestedPath.isNotEmpty) lastPaths[bottomNavIndex] = requestedPath;
    bottomNavIndex = index;
    List<String>? newPath =
        (lastPaths.containsKey(index)) ? lastPaths[index] : null;
    selectedSorting = 0;
    switch (index) {
      case 0:
        newPath ??= const ['gcodes'];
        break;
      case 1:
        newPath ??= const ['config'];
        break;
      default:
      // Do nothing
    }

    _busyFetchDirectoryData(newPath: newPath!);
  }

  onCreateDirTapped(BuildContext context) async {
    DialogResponse? dialogResponse = await _dialogService.showCustomDialog(
        variant: DialogType.renameFile,
        title: tr('dialogs.create_folder.title'),
        description: tr('dialogs.create_folder.label'),
        mainButtonTitle: tr('general.create'),
        secondaryButtonTitle: MaterialLocalizations.of(context)
                .cancelButtonLabel
                .capitalizeFirst ??
            'Cancel',
        data: RenameFileDialogArguments(
            initialValue: '',
            matchPattern: '^[A-z0-9._\-]+\$'));
    if (dialogResponse?.confirmed ?? false) {
      String folderName = dialogResponse!.data;

      setBusyForObject(this, true);
      notifyListeners();
      try {
        await _fileService!.createDir('$requestedPathAsString/$folderName');
      } on JRpcError catch (e) {
        _snackBarService.showCustomSnackBar(
            variant: SnackbarType.error,
            duration: const Duration(seconds: 5),
            title: 'Error',
            message: 'Could not create folder!\n${e.message}');
        setBusyForObject(this, false);
        notifyListeners();
      }
    }
  }

  onDeleteFileTapped(BuildContext context, String fileName) async {
    var materialLocalizations = MaterialLocalizations.of(context);
    DialogResponse? dialogResponse =
        await _dialogService.showConfirmationDialog(
            title: tr('dialogs.delete_folder.title'),
            description: tr('dialogs.delete_file.description',args: [fileName]),
            dialogPlatform: DialogPlatform.Material,
            confirmationTitle: materialLocalizations.deleteButtonTooltip,
            cancelTitle:
                materialLocalizations.cancelButtonLabel.capitalizeFirst ??
                    'Cancel');

    if (dialogResponse?.confirmed ?? false) {
      setBusyForObject(this, true);
      notifyListeners();
      try {
        await _fileService!.deleteFile('$requestedPathAsString/$fileName');
      } on JRpcError catch (e) {
        _snackBarService.showCustomSnackBar(
            variant: SnackbarType.error,
            duration: const Duration(seconds: 5),
            title: 'Error',
            message: 'Could not perform rename.\n${e.message}');
        setBusyForObject(this, false);
        notifyListeners();
      }
    }
  }

  onDeleteDirTapped(BuildContext context, String fileName) async {
    var materialLocalizations = MaterialLocalizations.of(context);
    DialogResponse? dialogResponse = await _dialogService.showConfirmationDialog(
        title: tr('dialogs.delete_folder.title'),
        description: tr('dialogs.delete_folder.description',args: [fileName]),
        dialogPlatform: DialogPlatform.Material,
        confirmationTitle: materialLocalizations.deleteButtonTooltip,
        cancelTitle: materialLocalizations.cancelButtonLabel.capitalizeFirst ??
            'Cancel');

    if (dialogResponse?.confirmed ?? false) {
      setBusyForObject(this, true);
      notifyListeners();
      try {
        await _fileService!.deleteDirForced('$requestedPathAsString/$fileName');
      } on JRpcError catch (e) {
        _snackBarService.showCustomSnackBar(
            variant: SnackbarType.error,
            duration: const Duration(seconds: 5),
            title: 'Error',
            message: 'Could not perform rename.\n${e.message}');
        setBusyForObject(this, false);
        notifyListeners();
      }
    }
  }

  onRenameFileTapped(BuildContext context, String fileName) async {
    List<String> fileNames = [];
    fileNames.addAll(_folderContent.folders.map((e) => e.name));
    fileNames.addAll(_folderContent.files.map((e) => e.name));
    fileNames.remove(fileName);

    DialogResponse? dialogResponse = await _dialogService.showCustomDialog(
        variant: DialogType.renameFile,
        title: tr('dialogs.rename_file.title'),
        description: tr('dialogs.rename_file.label'),
        mainButtonTitle: tr('general.rename'),
        secondaryButtonTitle: MaterialLocalizations.of(context)
                .cancelButtonLabel
                .capitalizeFirst ??
            'Cancel',
        data: RenameFileDialogArguments(
            initialValue: fileName,
            blocklist: fileNames,
            fileExt: 'gcode',
            matchPattern: '^[A-z0-9.#+_\-]+\$'));
    if (dialogResponse != null && dialogResponse.confirmed) {
      String newName = dialogResponse.data;
      if (newName == fileName) return;
      setBusyForObject(this, true);
      notifyListeners();
      try {
        await _fileService!.moveFile('$requestedPathAsString/$fileName',
            '$requestedPathAsString/$newName');
      } on JRpcError catch (e) {
        _snackBarService.showCustomSnackBar(
            variant: SnackbarType.error,
            duration: const Duration(seconds: 5),
            title: 'Error',
            message: 'Could not perform rename.\n${e.message}');
        setBusyForObject(this, false);
        notifyListeners();
      }
    }
  }

  onRenameDirTapped(BuildContext context, String fileName) async {
    List<String> fileNames = [];
    fileNames.addAll(_folderContent.folders.map((e) => e.name));
    fileNames.addAll(_folderContent.files.map((e) => e.name));
    fileNames.remove(fileName);

    DialogResponse? dialogResponse = await _dialogService.showCustomDialog(
        variant: DialogType.renameFile,
        title: tr('dialogs.rename_folder.title'),
        description: tr('dialogs.rename_folder.label'),
        mainButtonTitle: tr('general.rename'),
        secondaryButtonTitle: MaterialLocalizations.of(context)
                .cancelButtonLabel
                .capitalizeFirst ??
            'Cancel',
        data: RenameFileDialogArguments(
            initialValue: fileName,
            blocklist: fileNames,
            matchPattern: '^[A-z0-9._\-]+\$'));
    if (dialogResponse?.confirmed ?? false) {
      String newName = dialogResponse!.data;
      if (newName == fileName) return;
      setBusyForObject(this, true);
      notifyListeners();
      try {
        await _fileService!.moveFile('$requestedPathAsString/$fileName',
            '$requestedPathAsString/$newName');
      } on JRpcError catch (e) {
        _snackBarService.showCustomSnackBar(
            variant: SnackbarType.error,
            duration: const Duration(seconds: 5),
            title: 'Error',
            message: 'Could not perform rename.\n${e.message}');
        setBusyForObject(this, false);
        notifyListeners();
      }
    }
  }

  handleFileListChanged(
      FileListChangedNotification fileListChangedNotification) {
    _logger.i('CrntPath: $requestedPathAsString');
    _logger.i('$fileListChangedNotification');

    FileListChangedItem item = fileListChangedNotification.item;
    var itemWithInLevel = isWithin(requestedPathAsString, item.fullPath);

    FileListChangedSourceItem? srcItem = fileListChangedNotification.sourceItem;
    var srcItemWithInLevel =
        isWithin(requestedPathAsString, srcItem?.fullPath ?? '');

    if ((itemWithInLevel < 0 || itemWithInLevel > 1) &&
        (srcItemWithInLevel < 0 || srcItemWithInLevel > 1)) {
      return;
    }

    _busyFetchDirectoryData(newPath: requestedPath);
  }

  onRefresh() {
    _busyFetchDirectoryData(newPath: folderContent.reqPath.split('/'))
        .then((value) => refreshController.refreshCompleted());
  }

  onFileTapped(GCodeFile file) {
    _navigationService.navigateTo(Routes.fileDetailView,
        arguments: FileDetailViewArguments(file: file));
  }

  onFolderPressed(Folder folder) {
    List<String> newPath = folderContent.reqPath.split('/');
    newPath.add(folder.name);
    _busyFetchDirectoryData(newPath: newPath);
  }

  onBreadCrumbItemPressed(List<String> newPath) {
    return _busyFetchDirectoryData(newPath: newPath);
  }

  Future<bool> onWillPop() async {
    List<String> newPath = folderContent.reqPath.split('/');

    if (isSearching) {
      stopSearching();
      return false;
    } else if (newPath.length > 1 && !isBusy) {
      newPath.removeLast();
      _busyFetchDirectoryData(newPath: newPath);
      return false;
    }
    return true;
  }

  onPopFolder() async {
    List<String> newPath = folderContent.reqPath.split('/');
    if (newPath.length > 1 && !isBusy) {
      newPath.removeLast();
      _busyFetchDirectoryData(newPath: newPath);
      return false;
    }
    return true;
  }

  startSearching() {
    isSearching = true;
    notifyListeners();
  }

  stopSearching() {
    isSearching = false;
    notifyListeners();
  }

  resetSearchQuery() {
    searchEditingController.text = '';
    notifyListeners();
  }

  Future _fetchDirectoryData({List<String> newPath = const ['gcodes']}) {
    requestedPath = newPath;
    return _folderContentStreamController.addStream(_fileService!
        .fetchDirectoryInfo(requestedPathAsString, true)
        .asStream());
  }

  Future _busyFetchDirectoryData({List<String> newPath = const ['gcodes']}) {
    return runBusyFuture(_fetchDirectoryData(newPath: newPath));
  }

  int comperatorName(File a, File b) => a.name.compareTo(b.name);

  int comperatorModified(File a, File b) => b.modified.compareTo(a.modified);

  int comperatorPrintStart(File fileA, File fileB) {
    GCodeFile a = fileA as GCodeFile;
    GCodeFile b = fileB as GCodeFile;
    return b.printStartTime?.compareTo(a.printStartTime ?? 0) ?? -1;
  }

  onSortSelected(int index) {
    selectedSorting = index;
    notifyListeners();
  }

  FolderContentWrapper get folderContent {
    FolderContentWrapper fullContent = _folderContent;
    List<Folder> folders = _folderContent.folders.toList(growable: false);
    List<File> files = _folderContent.files.toList(growable: false);

    String queryTerm = searchEditingController.text.toLowerCase();

    if (queryTerm.isNotEmpty && isSearching) {
      List<String> terms = queryTerm.split(RegExp('\\W+'));
      RegExp regExp =
          RegExp(terms.where((element) => element.isNotEmpty).join("|"));
      folders = folders
          .where((element) =>
              terms.every((t) => element.name.toLowerCase().contains(t)))
          .toList(growable: false);

      files = files
          .where((element) =>
              terms.every((t) => element.name.toLowerCase().contains(t)))
          .toList(growable: false);
    }
    var folderComparator = folderComparators[selectedSorting];
    if (folderComparator != null) folders.sort(folderComparator);
    files.sort(fileComparators[selectedSorting]);

    return FolderContentWrapper(fullContent.reqPath, folders, files);
  }

  bool get isFolderContentAvailable => dataReady(_FolderContentStreamKey);

  FolderContentWrapper get _folderContent => dataMap![_FolderContentStreamKey];

  bool get isServerAvailable => dataReady(_ServerStreamKey);

  KlipperInstance get server => dataMap![_ServerStreamKey];

  bool get isMachineAvailable => dataReady(_SelectedPrinterStreamKey);

  Machine? get selectedPrinter => dataMap?[_SelectedPrinterStreamKey];

  bool get isSubFolder => folderContent.reqPath.split('/').length > 1;

  String? get curPathToPrinterUrl {
    if (_machine != null) {
      return '${_machine!.httpUrl}/server/files';
    }
    return null;
  }

  @override
  dispose() {
    super.dispose();
    refreshController.dispose();
    searchEditingController.dispose();
  }
}
