
import 'package:mobileraker/data/model/moonraker/machine_settings.dart';

abstract class MachineSettingsRepository {
  Future<void> update(MachineSettings machineSettings);

  Future<MachineSettings?> get();
}