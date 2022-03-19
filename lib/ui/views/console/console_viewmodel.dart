import 'package:flutter/cupertino.dart';
import 'package:mobileraker/app/app_setup.locator.dart';
import 'package:mobileraker/app/app_setup.logger.dart';
import 'package:mobileraker/domain/printer_setting.dart';
import 'package:mobileraker/dto/console/console_entry.dart';
import 'package:mobileraker/dto/server/klipper.dart';
import 'package:mobileraker/service/klippy_service.dart';
import 'package:mobileraker/service/machine_service.dart';
import 'package:mobileraker/service/printer_service.dart';
import 'package:mobileraker/service/setting_service.dart';
import 'package:mobileraker/ui/dialog/action_dialogs.dart';
import 'package:mobileraker/ui/views/setting/setting_viewmodel.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

const String _SelectedPrinterStreamKey = 'selectedPrinter';
const String _gCodeNotifyResp = 'notifyGcodeResp';
const String _ConsoleHistory = 'consoleHistory';
const String _ServerStreamKey = 'server';

class ConsoleViewModel extends MultipleStreamViewModel {
  final _logger = getLogger('ConsoleViewModel');

  final _navigationService = locator<NavigationService>();
  final _dialogService = locator<DialogService>();
  final _machineService = locator<MachineService>();
  final _settingService = locator<SettingService>();

  PrinterSetting? _printerSetting;

  KlippyService? get _klippyService => _printerSetting?.klippyService;

  PrinterService? get _printerService => _printerSetting?.printerService;

  RefreshController refreshController =
      RefreshController(initialRefresh: false);
  TextEditingController textEditingController = TextEditingController();

  bool get isConsoleHistoryAvailable => dataReady(_ConsoleHistory);

  List<ConsoleEntry> get consoleEntries => dataMap![_ConsoleHistory];

  bool get isServerAvailable => dataReady(_ServerStreamKey);

  KlipperInstance get server => dataMap![_ServerStreamKey];

  bool get canUseEms =>
      isServerAvailable && server.klippyState == KlipperState.ready;

  bool get canSendCommand =>
      isServerAvailable &&
      server.klippyState == KlipperState.ready &&
      server.klippyConnected;

  @override
  Map<String, StreamData> get streamsMap => {
        _SelectedPrinterStreamKey:
            StreamData<PrinterSetting?>(_machineService.selectedMachine),
        if (_klippyService != null) ...{
          _ServerStreamKey:
              StreamData<KlipperInstance>(_klippyService!.klipperStream)
        },
        if (_printerService != null) ...{
          _ConsoleHistory: StreamData<List<ConsoleEntry>>(
              _printerService!.gcodeStore().asStream()),
          _gCodeNotifyResp: StreamData<String>(
              _printerService!.gCodeResponseStream,
              transformData: _transformGCodeResponse)
        }
      };

  ConsoleEntry _transformGCodeResponse(String gCodeResp) {
    return ConsoleEntry(gCodeResp, ConsoleEntryType.RESPONSE,
        DateTime.now().millisecondsSinceEpoch / 1000);
  }

  onRefresh() async {
    notifySourceChanged(clearOldData: true);
    refreshController.refreshCompleted();
  }

  onCommandTap(ConsoleEntry consoleEntry) {
    if (consoleEntry.type != ConsoleEntryType.COMMAND) {
      _logger.w('Tried executing a non COMMAND command');
      return;
    }
    textEditingController.text = consoleEntry.message;
    textEditingController.selection = TextSelection.fromPosition(
      TextPosition(offset: textEditingController.text.length),
    );
  }

  onCommandSubmit() {
    String? command = textEditingController.text;
    if (textEditingController.text.isEmpty)
      return;
    consoleEntries.add(ConsoleEntry(command, ConsoleEntryType.COMMAND,
        DateTime.now().millisecondsSinceEpoch / 1000));
    textEditingController.text = '';
    _printerService?.gCode(command);
  }

  @override
  onData(String key, data) {
    super.onData(key, data);
    switch (key) {
      case _SelectedPrinterStreamKey:
        PrinterSetting? nPrinterSetting = data;
        if (nPrinterSetting == _printerSetting) break;
        _printerSetting = nPrinterSetting;
        notifySourceChanged(clearOldData: true);
        break;
      case _gCodeNotifyResp:
        consoleEntries.add(data);
        break;
      case _ConsoleHistory:
        _logger.w("Received ConsoleHist");
        break;
      default:
        break;
    }
  }

  onEmergencyPressed() {
    if (_settingService.readBool(emsKey))
      emergencyStopConfirmDialog(_dialogService).then((dialogResponse) {
        if (dialogResponse?.confirmed ?? false) _klippyService?.emergencyStop();
      });
    else
      _klippyService?.emergencyStop();
  }

  @override
  void dispose() {
    super.dispose();
    refreshController.dispose();
  }
}