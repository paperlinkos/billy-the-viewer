import 'package:flutter/material.dart';
import 'package:billy_the_viewer/app/app.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = CampaignRepository();
  await repository.initialize();
  await repository.registerSecondDemoCampaign();
  runApp(const BillyApp());
}
