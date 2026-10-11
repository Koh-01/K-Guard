import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../app_ui.dart';
import '../settings.dart';
import '../widgets.dart';

/// Guard login: pick your name, enter your PIN.
class LoginScreen extends StatelessWidget {
  final VoidCallback onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

  Future<void> _login(BuildContext context, Guard g) async {
    final pin = await askPin(context, 'Hi ${g.name}, enter your PIN');
    if (pin == null || !context.mounted) return;
    if (pin != g.pin) {
      toast(context, 'Wrong PIN');
      return;
    }
    AppSettings.currentGuard = g.name;
    onLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    final guards = AppSettings.guards;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: EdgeInsets.fromLTRB(
            constraints.maxWidth < 400 ? 16 : 24, 28, 24, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.hairline(context),
                                spreadRadius: 1),
                          ],
                        ),
                        child: Image.asset('assets/icon/logo.png',
                            filterQuality: FilterQuality.medium),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start your patrol',
                                style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 5),
                            Text('Select your profile to continue securely.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  AppSectionHeader('Guard profiles',
                      caption: guards.isEmpty
                          ? 'Accounts are managed from Settings.'
                          : '${guards.length} ${guards.length == 1 ? 'profile' : 'profiles'} available'),
                  const SizedBox(height: 14),
                  if (guards.isEmpty)
                    const AppEmptyState(
                      icon: Icons.person_off_outlined,
                      title: 'No guard accounts',
                      message:
                          'Open Settings to create the first guard profile.',
                    )
                  else
                    GridView.count(
                      crossAxisCount: constraints.maxWidth >= 560 ? 3 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio:
                          constraints.maxWidth < 480 ? 1.05 : 1.25,
                      children: [
                        for (final g in guards)
                          AppSurface(
                            onTap: () => _login(context, g),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color:
                                        theme.colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    g.name.characters.first.toUpperCase(),
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(g.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium),
                                const SizedBox(height: 2),
                                Text('Tap to sign in',
                                    style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  if (AppSettings.supportContact.trim().isNotEmpty) ...[
                    const SizedBox(height: 32),
                    AppSurface(
                      padding: const EdgeInsets.all(16),
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppIconBox(Icons.support_agent_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Technical support',
                                    style: theme.textTheme.titleSmall),
                                const SizedBox(height: 4),
                                SelectableText(
                                  AppSettings.supportContact.trim(),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
