import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config/server_endpoint.dart';
import 'core/di/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve the backend address before any service touches the network: a
  // saved address for this device wins over the one compiled into the build.
  await ServerEndpoint.load();
  if (ServerEndpoint.isOverridden) {
    dioClient.setBaseUrl(ServerEndpoint.current);
  }

  initServices();
  runApp(const SynoraApp());
}
