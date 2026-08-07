import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/l10n/generated/app_localizations.dart';
import '../providers/pro_profile.dart';
import '../widgets/cmp_profile_form.dart';

class UiProfile extends StatelessWidget {
  const UiProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proProfile = context.watch<ProProfile>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profilePageTitle)),
      body: proProfile.isLoading
          ? const Center(child: CircularProgressIndicator())
          : proProfile.profile == null
          ? Center(child: Text(proProfile.errorMessage ?? ''))
          : SingleChildScrollView(
              child: CmpProfileForm(
                key: ValueKey(proProfile.profile!.id),
                profile: proProfile.profile!,
                errorMessage: proProfile.errorMessage,
                onSave: (profile) =>
                    context.read<ProProfile>().updateProfile(profile),
              ),
            ),
    );
  }
}
