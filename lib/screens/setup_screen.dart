import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../services/demo_service.dart';
import '../services/mdns_service.dart';
import '../themes/base/theme_registry.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _libraryNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController(
    text: 'admin',
  );
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _libraryNameController.text = themeProvider.setupLibraryName;
    _libraryNameController.text = themeProvider.setupLibraryName;
    // Removed listener to prevent rebuilds on every keystroke which causes focus loss
  }

  @override
  void dispose() {
    _libraryNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ensure themes are initialized
    ThemeRegistry.initialize();

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        // Get locale and step
        String t(String key) => TranslationService.translate(context, key);
        final currentStep = themeProvider.setupStep;

        return Scaffold(
          appBar: AppBar(
            title: Text(t('onboarding_welcome_title')),
            automaticallyImplyLeading: false, // Hide back button
          ),
          body: Stepper(
            physics:
                const ClampingScrollPhysics(), // Ensure scrolling works well
            currentStep: currentStep,
            onStepContinue: () {
              debugPrint(
                'Stepper onStepContinue called - currentStep: $currentStep',
              );
              if (currentStep < 5) {
                if (currentStep == 1) {
                  // Validate library name is not empty
                  if (_libraryNameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          TranslationService.translate(
                                context,
                                'library_name_required',
                              ) ??
                              'Le nom de la bibliothèque est requis',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  // Save library name when leaving step 1
                  themeProvider.setSetupLibraryName(
                    _libraryNameController.text.trim(),
                  );
                }
                // Validate password on credentials step (now step 4)
                if (currentStep == 4) {
                  if (_passwordController.text.isNotEmpty &&
                      _passwordController.text !=
                          _confirmPasswordController.text) {
                    setState(
                      () => _passwordError =
                          TranslationService.translate(
                            context,
                            'passwords_do_not_match',
                          ) ??
                          'Passwords do not match',
                    );
                    return;
                  }
                  setState(() => _passwordError = null);
                }
                themeProvider.setSetupStep(currentStep + 1);
              } else {
                debugPrint('Calling _finishSetup...');
                _finishSetup(context);
              }
            },
            onStepTapped: (step) {
              // Only allow tapping valid past/current steps or next step
              // But strictly prevent jumping way ahead (like from 1 to 6)
              if (step <= themeProvider.setupStep + 1) {
                themeProvider.setSetupStep(step);
              }
            },
            onStepCancel: () {
              if (currentStep > 0) {
                themeProvider.setSetupStep(currentStep - 1);
              }
            },
            controlsBuilder: (context, details) {
              final isLastStep = currentStep == 5;
              return Padding(
                padding: const EdgeInsets.only(top: 24.0, bottom: 12.0),
                child: Row(
                  children: [
                    // Using Container + InkWell instead of ElevatedButton to avoid
                    // AnimatedDefaultTextStyle animation issues during theme transitions
                    Material(
                      color: Colors.blue.shade700,
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: Key('setupNextButton_${details.stepIndex}'),
                        onTap: () {
                          details.onStepContinue?.call();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: Text(
                            isLastStep
                                ? t('setup_btn_finish')
                                : t('setup_btn_next'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (currentStep > 0) ...[
                      const SizedBox(width: 16),
                      // Using InkWell + Text instead of TextButton to avoid
                      // AnimatedDefaultTextStyle animation issues during theme transitions
                      InkWell(
                        onTap: details.onStepCancel,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            t('setup_btn_back'),
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
            steps: [
              // Step 0: Welcome
              Step(
                title: Text(t('setup_welcome_title')),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('onboarding_welcome_title'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(t('onboarding_welcome_desc')),
                  ],
                ),
                isActive: currentStep >= 0,
                state: currentStep > 0 ? StepState.complete : StepState.indexed,
              ),
              // Step 1: Profile & Library Info
              Step(
                title: Text(t('setup_library_info_title')),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('setup_library_name_label'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('setupLibraryNameField'),
                      controller: _libraryNameController,
                      decoration: InputDecoration(
                        hintText: t('setup_library_name_hint'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                isActive: currentStep >= 1,
                state: currentStep > 1 ? StepState.complete : StepState.indexed,
              ),
              // Step 2: Profile Type
              Step(
                title: Text(t('setup_profile_step_title')),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('setup_profile_step_desc'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    _ProfileCard(
                      icon: Icons.menu_book,
                      label: t('profile_reader'),
                      description: t('profile_reader_desc'),
                      selected: themeProvider.setupProfileType == 'reader',
                      onTap: () =>
                          themeProvider.setSetupProfileType('reader'),
                    ),
                    const SizedBox(height: 8),
                    _ProfileCard(
                      icon: Icons.local_library,
                      label: t('profile_librarian'),
                      description: t('profile_librarian_desc'),
                      selected: themeProvider.setupProfileType == 'librarian',
                      onTap: () =>
                          themeProvider.setSetupProfileType('librarian'),
                    ),
                    const SizedBox(height: 8),
                    _ProfileCard(
                      icon: Icons.storefront,
                      label: t('profile_bookseller'),
                      description: t('profile_bookseller_desc'),
                      selected: themeProvider.setupProfileType == 'bookseller',
                      onTap: () =>
                          themeProvider.setSetupProfileType('bookseller'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t('setup_profile_coming_soon'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProfileCard(
                      icon: Icons.family_restroom,
                      label: t('profile_family'),
                      description: t('profile_family_desc'),
                      enabled: false,
                    ),
                    const SizedBox(height: 8),
                    _ProfileCard(
                      icon: Icons.school,
                      label: t('profile_educator'),
                      description: t('profile_educator_desc'),
                      enabled: false,
                    ),
                    const SizedBox(height: 8),
                    _ProfileCard(
                      icon: Icons.groups,
                      label: t('profile_association'),
                      description: t('profile_association_desc'),
                      enabled: false,
                    ),
                  ],
                ),
                isActive: currentStep >= 2,
                state: currentStep > 2 ? StepState.complete : StepState.indexed,
              ),
              // Step 3: Demo Content
              Step(
                title: Text(t('setup_demo_title')),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('setup_demo_header'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(t('setup_demo_body')),
                    const SizedBox(height: 16),
                    RadioListTile<bool>(
                      title: Text(t('setup_demo_yes')),
                      value: true,
                      groupValue: themeProvider.setupImportDemo,
                      onChanged: (val) =>
                          themeProvider.setSetupImportDemo(val!),
                    ),
                    RadioListTile<bool>(
                      key: const Key('setupDemoNo'),
                      title: Text(t('setup_demo_no')),
                      value: false,
                      groupValue: themeProvider.setupImportDemo,
                      onChanged: (val) =>
                          themeProvider.setSetupImportDemo(val!),
                    ),
                  ],
                ),
                isActive: currentStep >= 3,
                state: currentStep > 3 ? StepState.complete : StepState.indexed,
              ),
              // Step 4: Credentials
              Step(
                title: Text(
                  TranslationService.translate(
                        context,
                        'setup_credentials_title',
                      ) ??
                      'Credentials',
                ),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(
                            context,
                            'setup_password_optional',
                          ) ??
                          'Optional - Set a password to protect your library',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('setupUsernameField'),
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText:
                            TranslationService.translate(
                              context,
                              'setup_username_label',
                            ) ??
                            'Username',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('setupPasswordField'),
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText:
                            TranslationService.translate(
                              context,
                              'setup_password_label',
                            ) ??
                            'Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        helperText:
                            TranslationService.translate(
                              context,
                              'leave_empty_no_password',
                            ) ??
                            'Leave empty for no password',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('setupConfirmPasswordField'),
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText:
                            TranslationService.translate(
                              context,
                              'setup_confirm_password',
                            ) ??
                            'Confirm Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: _passwordError,
                      ),
                    ),
                  ],
                ),
                isActive: currentStep >= 4,
                state: currentStep > 4 ? StepState.complete : StepState.indexed,
              ),
              // Step 5: Finish
              Step(
                title: Text(t('setup_finish_title')),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('setup_finish_header'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(t('setup_finish_body')),
                  ],
                ),
                isActive: currentStep >= 5,
                state: currentStep == 5
                    ? StepState.complete
                    : StepState.indexed,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _finishSetup(BuildContext context) async {
    debugPrint('_finishSetup: Starting...');

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(child: CircularProgressIndicator()),
    );
    debugPrint('_finishSetup: Dialog shown');

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      debugPrint('_finishSetup: Got services');

      // 1. Setup Backend
      final profileType = themeProvider.setupProfileType;
      debugPrint('_finishSetup: Calling apiService.setup (profile: $profileType)...');
      await apiService.setup(
        libraryName: themeProvider.setupLibraryName,
        profileType: profileType,
        theme: themeProvider.themeStyle,
      );
      debugPrint('_finishSetup: apiService.setup completed');

      // 2. Apply preset modules for the selected profile
      debugPrint('_finishSetup: Applying preset: $profileType...');
      await themeProvider.applyPreset(profileType);
      debugPrint('_finishSetup: Preset applied');

      // 2. Import Demo Data if requested
      if (themeProvider.setupImportDemo) {
        debugPrint('_finishSetup: Importing demo data...');
        await DemoService.importDemoBooks(context);
        debugPrint('_finishSetup: Demo data imported');
      }

      debugPrint(
        '_finishSetup: Checking context.mounted (1): ${context.mounted}',
      );
      if (context.mounted) {
        // Close loading dialog FIRST to avoid build scope conflicts
        debugPrint('_finishSetup: Closing dialog...');
        Navigator.of(context).pop();
        debugPrint('_finishSetup: Dialog closed');

        // Wait for dialog animation to finish and frame to settle
        await Future.delayed(const Duration(milliseconds: 350));
        debugPrint('_finishSetup: Delay completed');

        // Only proceed if still mounted after delay
        debugPrint(
          '_finishSetup: Checking context.mounted (2): ${context.mounted}',
        );
        if (!context.mounted) return;

        // Use batch method to apply all settings with single notification
        // This is done AFTER dialog is fully closed to prevent dirty widget errors
        debugPrint('_finishSetup: Calling completeSetupWithSettings...');
        await themeProvider.completeSetupWithSettings(
          profileType: profileType,
          avatarConfig: themeProvider.setupAvatarConfig,
          libraryName: themeProvider.setupLibraryName,
          apiService: apiService,
        );
        debugPrint('_finishSetup: completeSetupWithSettings done');

        if (!context.mounted) return;

        final authService = Provider.of<AuthService>(context, listen: false);

        // Save username from setup (default 'admin' if empty)
        final username = _usernameController.text.trim().isNotEmpty
            ? _usernameController.text.trim()
            : 'admin';
        await authService.saveUsername(username);
        debugPrint('_finishSetup: Username saved: $username');

        // Save password if provided
        if (_passwordController.text.isNotEmpty) {
          await authService.savePassword(_passwordController.text);
          debugPrint('_finishSetup: Password saved');
        }

        // Auto-login the user after setup (no need to go to login page)
        // In local mode, we just need a token to mark the user as logged in
        await authService.saveToken(
          'local-setup-token-${DateTime.now().millisecondsSinceEpoch}',
        );
        debugPrint('_finishSetup: User auto-logged in');

        debugPrint('_finishSetup: COMPLETE - Navigating to dashboard...');

        // Restart mDNS with correct library name (was started with default in main)
        if (themeProvider.networkDiscoveryEnabled) {
          try {
            await MdnsService.stop(); // Stop existing announcement
            final libraryUuid = await authService.getOrCreateLibraryUuid();
            await MdnsService.startAnnouncing(
              themeProvider.libraryName,
              ApiService.httpPort,
              libraryId: libraryUuid,
            );
            await MdnsService.startDiscovery();
            debugPrint(
              '_finishSetup: mDNS restarted with name: ${themeProvider.libraryName}',
            );
          } catch (e) {
            debugPrint('_finishSetup: mDNS restart failed: $e');
          }
        }

        // Navigate directly to dashboard since user is now logged in
        if (context.mounted) {
          GoRouter.of(context).go('/dashboard');
        }
      } else {
        debugPrint(
          '_finishSetup: ERROR - context not mounted after apiService.setup!',
        );
      }
    } catch (e) {
      // Close loading dialog
      if (context.mounted) Navigator.of(context).pop();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'setup_failed')}: $e',
            ),
          ),
        );
      }
    }
  }
}

class _ProfileCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ProfileCard({
    required this.icon,
    required this.label,
    required this.description,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = enabled ? 1.0 : 0.45;

    return Opacity(
      opacity: opacity,
      child: Semantics(
        button: enabled,
        label: enabled ? '$label, $description' : '$label, ${TranslationService.translate(context, 'coming_soon')}',
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          elevation: selected ? 2 : 0,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 32,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            if (!enabled) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  TranslationService.translate(context, 'coming_soon'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
