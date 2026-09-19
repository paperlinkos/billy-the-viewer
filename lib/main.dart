import 'package:flutter/material.dart';
import 'package:billy_the_viewer/app/app.dart';
import 'package:billy_the_viewer/services/campaign_repository.dart';
import 'package:billy_the_viewer/services/supabase/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize local campaign repository with baseline demo campaigns
  final repository = CampaignRepository();
  await repository.initialize();
  await repository.registerSecondDemoCampaign();

  // 2. Initialize Supabase and asynchronously sync remote campaigns (non-fatal if offline)
  try {
    await SupabaseService().initialize();
    await repository.syncRemoteCampaigns();
  } catch (e) {
    debugPrint('Main: Supabase sync warning (offline or uninitialized): $e');
  }

  runApp(const BillyApp());
}
