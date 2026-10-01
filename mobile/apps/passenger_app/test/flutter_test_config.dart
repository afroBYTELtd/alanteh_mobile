import 'dart:async';

import 'package:asm_maps/asm_maps.dart';
import 'package:asm_maps/testing.dart';

// Widget tests have no native map, so every test gets the stand-in.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AsmMapView.debugBuilderOverride = asmFakeMapBuilder;
  await testMain();
}
