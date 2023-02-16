import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobileraker/data/data_source/json_rpc_client.dart';
import 'package:mobileraker/data/model/hive/machine.dart';
import 'package:mobileraker/exceptions.dart';
import 'package:mobileraker/service/machine_service.dart';
import 'package:mobileraker/service/moonraker/jrpc_fallback_service.dart';
import 'package:mobileraker/service/selected_machine_service.dart';
import 'package:mobileraker/util/extensions/async_ext.dart';
import 'package:mobileraker/util/ref_extension.dart';

final jrpcClientProvider = Provider.autoDispose.family<JsonRpcClient, String>(
    name: 'jrpcClientProvider', (ref, machineUUID) {
  // var machine = ref.watch(machineProvider(machineUUID)).valueOrFullNull;
  // if (machine == null) {
  //   throw MobilerakerException(
  //       'Machine with UUID "$machineUUID" was not found!');
  // }
  //
  // var jsonRpcClient = JsonRpcClientBuilder.fromMachine(machine).build();
  // ref.onDispose(jsonRpcClient.dispose);
  // return jsonRpcClient..openChannel();

  return ref.watch(activeClientProvider(machineUUID));
});

final jrpcClientStateProvider = StreamProvider.autoDispose
    .family<ClientState, String>(name: 'jrpcClientStateProvider',
        (ref, machineUUID) {
  return ref.watchAsSubject(activeClientStateProvider(machineUUID));

  // return ref.watch(jrpcClientProvider(machineUUID)).stateStream;
});

// final jrpcClientProvider = Provider.autoDispose.family<JsonRpcClient, String>(
//     name: 'jrpcClientProvider', (ref, machineUUID) {
//   var jrpcFallbackService =
//   ref.watch(jrpcFallbackServiceProvider(machineUUID: machineUUID));
//   return jrpcFallbackService.activeClient;
// });
//
// final jrpcClientStateProvider = StreamProvider.autoDispose
//     .family<ClientState, String>(name: 'jrpcClientStateProvider',
//         (ref, machineUUID) {
//       var jrpcFallbackService =
//       ref.watch(jrpcFallbackServiceProvider(machineUUID: machineUUID));
//
//       return jrpcFallbackService.stateStream;
//     });

final jrpcClientSelectedProvider = Provider.autoDispose<JsonRpcClient>(
    name: 'jrpcClientSelectedProvider', (ref) {
  var machine = ref.watch(selectedMachineProvider).value;
  if (machine == null) {
    throw const MobilerakerException('Machine was null!');
  }
  return ref.watch(jrpcClientProvider(machine.uuid));
});

final jrpcClientStateSelectedProvider = StreamProvider.autoDispose<ClientState>(
    name: 'jrpcClientStateSelectedProvider', (ref) async* {
  try {
    Machine machine = await ref.watchWhereNotNull(selectedMachineProvider);
    StreamController<ClientState> sc = StreamController<ClientState>();
    ref.onDispose(() {
      if (!sc.isClosed) {
        sc.close();
      }
    });

    ref.listen<AsyncValue<ClientState>>(jrpcClientStateProvider(machine.uuid),
        (previous, next) {
      next.when(
          data: (data) => sc.add(data),
          error: (err, st) => sc.addError(err, st),
          loading: () {
            if (previous != null) ref.invalidateSelf();
          });
    }, fireImmediately: true);

    yield* sc.stream;
  } on StateError catch (e, s) {
// Just catch it. It is expected that the future/where might not complete!
  }
});
