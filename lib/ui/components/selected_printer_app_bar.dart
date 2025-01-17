import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobileraker/service/selected_machine_service.dart';
import 'package:mobileraker/util/extensions/async_ext.dart';

final selectedPrinterAppBarController =
    StateNotifierProvider.autoDispose<SelectedPrinterAppBarController, void>(
        (ref) => SelectedPrinterAppBarController(ref));

class SelectedPrinterAppBarController extends StateNotifier<void> {
  SelectedPrinterAppBarController(AutoDisposeRef ref)
      : selectedMachineService = ref.watch(selectedMachineServiceProvider),
        super(null);
  final SelectedMachineService selectedMachineService;

  onHorizontalDragEnd(DragEndDetails endDetails) {
    double primaryVelocity = endDetails.primaryVelocity ?? 0;
    if (primaryVelocity < 0) {
      // Page forwards
      selectedMachineService.selectPreviousMachine();
    } else if (primaryVelocity > 0) {
      // Page backwards
      selectedMachineService.selectNextMachine();
    }
  }
}

class SwitchPrinterAppBar extends HookConsumerWidget
    implements PreferredSizeWidget {
  const SwitchPrinterAppBar({
    Key? key,
    required this.title,
    this.actions,
  }) : super(key: key);

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var selectedMachine = ref.watch(selectedMachineProvider).valueOrFullNull;
    return AppBar(
      centerTitle: false,
      title: GestureDetector(
        onHorizontalDragEnd: ref
            .watch(selectedPrinterAppBarController.notifier)
            .onHorizontalDragEnd,
        child: Text(
          '${selectedMachine?.name ?? 'Printer'} - $title',
          overflow: TextOverflow.fade,
        ),
      ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
