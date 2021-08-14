import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:mobileraker/ui/views/printers/components/printers_slidable_view.dart';
import 'package:mobileraker/ui/views/printers/printers_viewmodel.dart';
import 'package:stacked/stacked.dart';

class Printers extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<PrintersViewModel>.reactive(
        builder: (context, model, child) {
          return Scaffold(
            appBar: AppBar(
              title: Text("Printers"),
              actions: [
                IconButton(
                    onPressed: model.onAddPrinterPressed,
                    tooltip: 'Add Printer',
                    icon: Icon(Icons.add))
              ],
            ),
            body: getBody(model, context),

            floatingActionButtonLocation:
                FloatingActionButtonLocation.miniCenterFloat,
          );
        },
        viewModelBuilder: () => PrintersViewModel());
  }

  Widget getBody(PrintersViewModel model, BuildContext context) {
    var settings = model.fetchSettings();
    if (settings.isEmpty)
      return Center(
          child: Text(
        'Please add a Printer!',
        style: Theme.of(context).textTheme.headline5,
      ));

    return ListView.builder(
        itemCount: settings.length,
        itemBuilder: (context, index) {
          var cur = settings.elementAt(index);

          return PrintersSlidable(key: ValueKey(cur.uuid), printerSetting: cur);
        });
  }
}