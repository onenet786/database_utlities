import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api_client.dart';
import 'database_profile.dart';
import 'operation_result.dart';
import 'security_preference.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const DatabaseUtilitiesApp());
}

class DatabaseUtilitiesApp extends StatefulWidget {
  const DatabaseUtilitiesApp({super.key});

  @override
  State<DatabaseUtilitiesApp> createState() => _DatabaseUtilitiesAppState();
}

class _DatabaseUtilitiesAppState extends State<DatabaseUtilitiesApp>
    with WidgetsBindingObserver {
  bool _isUnlocked = false;
  bool _isSplashComplete = false;
  UserType _currentUserType = UserType.admin;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _splashTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSplashComplete = true;
      });
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _lockSession();
    }
  }

  void _unlockSession(UserType userType) {
    setState(() {
      _currentUserType = userType;
      _isUnlocked = true;
    });
  }

  void _lockSession() {
    if (!_isUnlocked) {
      return;
    }

    setState(() {
      _isUnlocked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0C5E77),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Database Utilities',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF3F6F8),
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 550),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: !_isSplashComplete
            ? const AppSplashScreen(key: ValueKey('splash'))
            : _isUnlocked
            ? DatabaseUtilityHomePage(
                key: const ValueKey('home'),
                userType: _currentUserType,
                onLockRequested: _lockSession,
              )
            : LaunchGatePage(
                key: const ValueKey('launch'),
                onUnlock: _unlockSession,
              ),
      ),
    );
  }
}

class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key});

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = Curves.easeInOut.transform(_controller.value);
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF071E26),
                  Color(0xFF0F4C5C),
                  Color(0xFFE8A46F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: -120 + (pulse * 30),
                  left: -90,
                  child: _GlowOrb(
                    color: const Color(0x6633D6C9),
                    size: 260 + (pulse * 20),
                  ),
                ),
                Positioned(
                  bottom: -140,
                  right: -70 + (pulse * 25),
                  child: _GlowOrb(
                    color: const Color(0x55FFB36D),
                    size: 300 - (pulse * 30),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 0.92 + (pulse * 0.08),
                        child: const AppBrandMark(size: 112, showHalo: true),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Database Utilities',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Opacity(
                        opacity: 0.72 + (pulse * 0.28),
                        child: Text(
                          'Secure attach, detach, and role-aware database operations',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: const Color(0xFFE7EEF3)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LaunchGatePage extends StatefulWidget {
  const LaunchGatePage({super.key, required this.onUnlock});

  final ValueChanged<UserType> onUnlock;

  @override
  State<LaunchGatePage> createState() => _LaunchGatePageState();
}

class _LaunchGatePageState extends State<LaunchGatePage> {
  final _passwordController = TextEditingController();
  final ApiClient _apiClient = ApiClient(
    baseUrl: dotenv.env['API_BASE_URL'] ?? '',
  );

  String? _errorMessage;
  bool _isLaunchPasswordVisible = false;
  bool _isLoadingPreference = true;
  bool _isSubmitting = false;
  UserType _selectedUserType = UserType.admin;

  String get _expectedPassword {
    final now = DateTime.now();
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final day = now.day.toString().padLeft(2, '0');
    final month = months[now.month - 1];
    final year = now.year.toString();
    return 'OneNet$day$month$year';
  }

  @override
  void initState() {
    super.initState();
    _loadSecurityPreference();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSecurityPreference() async {
    try {
      final preference = await _apiClient.fetchSecurityPreference();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedUserType = preference.defaultUserType;
        _isLoadingPreference = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingPreference = false;
      });
    }
  }

  Future<void> _unlock() async {
    if (_passwordController.text.trim() != _expectedPassword) {
      setState(() {
        _errorMessage = 'Invalid launch password for today.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await _apiClient.saveSecurityPreference(
        SecurityPreference(defaultUserType: _selectedUserType),
      );
      if (!mounted) {
        return;
      }
      widget.onUnlock(_selectedUserType);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Could not save security preference. Details: $error';
        _isSubmitting = false;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final introText = _selectedUserType == UserType.admin
        ? 'Admin mode unlocks full configuration management, security settings, and attach-detach operations.'
        : 'User mode keeps the experience focused on attaching and detaching saved databases only.';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE8F2F4), Color(0xFFF7F3ED), Color(0xFFFFFCFA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AppBrandMark(size: 58),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Launch Security',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0A2540),
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Choose your role, verify the daily password, and continue securely.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF4F6478),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _SecuritySpotlightCard(
                          title: _selectedUserType == UserType.admin
                              ? 'Administrator Access'
                              : 'Restricted User Access',
                          description: introText,
                          accent: _selectedUserType == UserType.admin
                              ? const Color(0xFF0E7490)
                              : const Color(0xFFE07A5F),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'User Type',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF113247),
                              ),
                        ),
                        const SizedBox(height: 12),
                        IgnorePointer(
                          ignoring: _isLoadingPreference || _isSubmitting,
                          child: SegmentedButton<UserType>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: UserType.admin,
                                icon: Icon(Icons.admin_panel_settings_outlined),
                                label: Text('Admin'),
                              ),
                              ButtonSegment(
                                value: UserType.user,
                                icon: Icon(Icons.person_outline),
                                label: Text('User'),
                              ),
                            ],
                            selected: {_selectedUserType},
                            onSelectionChanged: (selection) {
                              setState(() {
                                _selectedUserType = selection.first;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_isLaunchPasswordVisible,
                          onSubmitted: (_) => _isSubmitting ? null : _unlock(),
                          decoration: InputDecoration(
                            labelText: 'Launch password',
                            hintText: 'OneNet21Mar2026',
                            errorText: _errorMessage,
                            prefixIcon: const Icon(Icons.password_outlined),
                            suffixIcon: IconButton(
                              tooltip: _isLaunchPasswordVisible
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () {
                                setState(() {
                                  _isLaunchPasswordVisible =
                                      !_isLaunchPasswordVisible;
                                });
                              },
                              icon: Icon(
                                _isLaunchPasswordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFD8E2EC)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.shield_moon_outlined,
                                color: Color(0xFF0E7490),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _isLoadingPreference
                                      ? 'Loading saved security preference from MySQL...'
                                      : 'Selected role is persisted in MySQL for the next launch.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF4F6478),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSubmitting || _isLoadingPreference
                                ? null
                                : _unlock,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_outlined),
                            label: Text(
                              _isSubmitting
                                  ? 'Securing Access...'
                                  : 'Unlock Workspace',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DatabaseUtilityHomePage extends StatefulWidget {
  const DatabaseUtilityHomePage({
    super.key,
    required this.userType,
    required this.onLockRequested,
  });

  final UserType userType;
  final VoidCallback onLockRequested;

  @override
  State<DatabaseUtilityHomePage> createState() =>
      _DatabaseUtilityHomePageState();
}

class _DatabaseUtilityHomePageState extends State<DatabaseUtilityHomePage> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController(text: r'.\SQLEXPRESS');
  final _databaseNameController = TextEditingController();
  final _mdfPathController = TextEditingController();
  final _ldfPathController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  AuthenticationMode _authenticationMode = AuthenticationMode.windows;
  List<DatabaseProfile> _profiles = [];
  bool _isLoadingProfiles = true;
  int? _editingIndex;
  int? _busyIndex;
  String? _lastMessage;
  String? _apiStatusMessage;
  bool _isSqlPasswordVisible = false;

  String get _apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';
  ApiClient get _apiClient => ApiClient(baseUrl: _apiBaseUrl);
  bool get _isAdmin => widget.userType == UserType.admin;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _databaseNameController.dispose();
    _mdfPathController.dispose();
    _ldfPathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoadingProfiles = true;
    });

    try {
      final apiStatusMessage = await _apiClient.fetchHealthMessage();
      final profiles = await _apiClient.fetchProfiles();
      if (!mounted) {
        return;
      }

      setState(() {
        _profiles = profiles;
        _isLoadingProfiles = false;
        _apiStatusMessage = apiStatusMessage;
        _lastMessage = profiles.isEmpty
            ? 'No saved settings found in MySQL yet.'
            : 'Loaded ${profiles.length} saved setting(s) from MySQL.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingProfiles = false;
        _apiStatusMessage = null;
        _lastMessage = 'Could not load saved settings. Details: $error';
      });
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _serverController.text = r'.\SQLEXPRESS';
    _databaseNameController.clear();
    _mdfPathController.clear();
    _ldfPathController.clear();
    _usernameController.clear();
    _passwordController.clear();
    _authenticationMode = AuthenticationMode.windows;
    _isSqlPasswordVisible = false;
    _editingIndex = null;
    setState(() {});
  }

  void _loadProfileForEditing(int index) {
    if (!_isAdmin) {
      return;
    }

    final profile = _profiles[index];
    _serverController.text = profile.server;
    _databaseNameController.text = profile.databaseName;
    _mdfPathController.text = profile.mdfPath;
    _ldfPathController.text = profile.ldfPath;
    _usernameController.text = profile.username;
    _passwordController.text = profile.password;
    _authenticationMode = profile.authenticationMode;
    _isSqlPasswordVisible = false;
    _editingIndex = index;
    setState(() {});
  }

  Future<void> _saveProfile() async {
    if (!_isAdmin || !_formKey.currentState!.validate()) {
      return;
    }

    final existingId = _editingIndex == null
        ? null
        : _profiles[_editingIndex!].id;
    final profile = DatabaseProfile(
      id: existingId,
      server: _serverController.text.trim(),
      databaseName: _databaseNameController.text.trim(),
      mdfPath: _mdfPathController.text.trim(),
      ldfPath: _ldfPathController.text.trim(),
      authenticationMode: _authenticationMode,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    setState(() {
      _lastMessage = existingId == null
          ? 'Saving settings to MySQL...'
          : 'Updating settings in MySQL...';
    });

    final result = await _apiClient.saveProfile(profile);
    if (!mounted) {
      return;
    }

    setState(() {
      _lastMessage = result.message;
    });

    if (result.success) {
      _clearForm();
      await _loadProfiles();
      if (!mounted) {
        return;
      }
    }

    _showOperationSnackBar(result);
  }

  Future<void> _deleteProfile(int index) async {
    if (!_isAdmin) {
      return;
    }

    final profile = _profiles[index];
    if (profile.id == null) {
      return;
    }

    setState(() {
      _busyIndex = index;
      _lastMessage = 'Deleting saved setting for ${profile.databaseName}...';
    });

    final result = await _apiClient.deleteProfile(profile.id!);
    if (!mounted) {
      return;
    }

    setState(() {
      _busyIndex = null;
      _lastMessage = result.message;
      if (result.success && _editingIndex == index) {
        _editingIndex = null;
      } else if (result.success &&
          _editingIndex != null &&
          _editingIndex! > index) {
        _editingIndex = _editingIndex! - 1;
      }
    });

    if (result.success) {
      await _loadProfiles();
    }

    _showOperationSnackBar(result);
  }

  Future<void> _attachDatabase(int index) async {
    final profile = _profiles[index];
    final shouldAttach = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Attach'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are about to attach ${profile.databaseName} to the configured SQL Server.',
              ),
              const SizedBox(height: 12),
              _dialogInfoLine('MDF', profile.mdfPath),
              if (profile.ldfPath.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _dialogInfoLine('LDF', profile.ldfPath),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Attach'),
            ),
          ],
        );
      },
    );

    if (shouldAttach != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blueGrey.shade700,
          content: Text('Attach cancelled for ${profile.databaseName}.'),
        ),
      );
      return;
    }

    await _runOperation(
      index: index,
      actionLabel: 'attach',
      request: _apiClient.attach,
    );
  }

  Future<void> _detachDatabase(int index) async {
    final profile = _profiles[index];
    final shouldDetach = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Detach'),
          content: Text(
            'Detaching ${profile.databaseName} will disconnect active users and rollback uncommitted transactions. Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Detach'),
            ),
          ],
        );
      },
    );

    if (shouldDetach != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blueGrey.shade700,
          content: Text('Detach cancelled for ${profile.databaseName}.'),
        ),
      );
      return;
    }

    await _runOperation(
      index: index,
      actionLabel: 'detach',
      request: _apiClient.detach,
    );
  }

  Future<void> _runOperation({
    required int index,
    required String actionLabel,
    required Future<OperationResult> Function(DatabaseProfile profile) request,
  }) async {
    final profile = _profiles[index];
    setState(() {
      _busyIndex = index;
      _lastMessage =
          'Sending $actionLabel request for ${profile.databaseName}...';
    });

    final result = await request(profile);
    if (!mounted) {
      return;
    }

    setState(() {
      _busyIndex = null;
      _lastMessage = result.message;
    });

    if (result.success) {
      try {
        final profiles = await _apiClient.fetchProfiles();
        if (!mounted) {
          return;
        }

        setState(() {
          _profiles = profiles;
        });
      } catch (error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _lastMessage = '${result.message} Status refresh failed: $error';
        });
      }
    }

    _showOperationSnackBar(result);
  }

  void _showOperationSnackBar(OperationResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.success
            ? Colors.green.shade700
            : Colors.red.shade700,
        content: Text(result.message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _isAdmin
        ? _buildAdminWorkspace(context)
        : _buildUserWorkspace(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Row(
          children: [
            const AppBrandMark(size: 34),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Database Utilities'),
                Text(
                  _isAdmin
                      ? 'Administrator workspace'
                      : 'Restricted operator workspace',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF4F6478),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: _RoleBadge(userType: widget.userType)),
          ),
          IconButton(
            tooltip: 'Reload settings',
            onPressed: _isLoadingProfiles ? null : _loadProfiles,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Lock workspace',
            onPressed: widget.onLockRequested,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF3F6F8), Color(0xFFF7FBFC)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _buildAdminWorkspace(BuildContext context) {
    final headline = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF0A2540),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1150;
        final header = _buildWorkspaceIntro(
          title: 'Admin Command Center',
          description:
              'Manage stored SQL Server profiles, enforce role-aware access, and run attach-detach operations from one secured workspace.',
        );
        final formPanel = _buildFormPanel(headline);
        final listPanel = _buildProfilesPanel(headline);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            header,
            const SizedBox(height: 20),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: formPanel),
                  const SizedBox(width: 20),
                  Expanded(flex: 6, child: listPanel),
                ],
              )
            else ...[
              formPanel,
              const SizedBox(height: 20),
              listPanel,
            ],
          ],
        );
      },
    );
  }

  Widget _buildUserWorkspace(BuildContext context) {
    final headline = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF0A2540),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildWorkspaceIntro(
          title: 'User Operations',
          description:
              'This protected view is intentionally limited. You can attach or detach saved databases, but configuration management stays reserved for administrators.',
        ),
        const SizedBox(height: 20),
        _buildProfilesPanel(headline),
      ],
    );
  }

  Widget _buildWorkspaceIntro({
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E3B4D), Color(0xFF0E7490), Color(0xFFE7A06A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppBrandMark(size: 58, compact: true),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFFE6F3F6),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _infoPill(_isAdmin ? 'Role: Admin' : 'Role: User'),
                    _infoPill('API secured'),
                    _infoPill('Session locks on minimize'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPanel(TextStyle? headline) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Server Settings', style: headline),
              const SizedBox(height: 8),
              Text(
                'Administrators can create or update the saved SQL Server profiles stored in MySQL.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF4F6478),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD8E2EC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Secure API Status',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF355468),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _apiBaseUrl.trim().isEmpty
                          ? 'API connection is not configured.'
                          : 'API connection is configured.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_apiStatusMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _apiStatusMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF4F6478),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _serverController,
                label: 'SQL Server instance',
                hint: r'.\SQLEXPRESS or localhost',
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _databaseNameController,
                label: 'Database name',
                hint: 'EmployeeDB',
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _mdfPathController,
                label: 'MDF file path',
                hint: r'C:\SQLData\EmployeeDB.mdf',
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _ldfPathController,
                label: 'LDF file path',
                hint: r'C:\SQLData\EmployeeDB_log.ldf (optional)',
              ),
              const SizedBox(height: 20),
              SegmentedButton<AuthenticationMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AuthenticationMode.windows,
                    label: Text('Windows Auth'),
                    icon: Icon(Icons.badge_outlined),
                  ),
                  ButtonSegment(
                    value: AuthenticationMode.sqlServer,
                    label: Text('SQL Login'),
                    icon: Icon(Icons.key_outlined),
                  ),
                ],
                selected: {_authenticationMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _authenticationMode = selection.first;
                  });
                },
              ),
              if (_authenticationMode == AuthenticationMode.sqlServer) ...[
                const SizedBox(height: 16),
                _buildField(
                  controller: _usernameController,
                  label: 'Username',
                  hint: 'sa',
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Enter SQL password',
                  obscureText: true,
                  isPasswordVisible: _isSqlPasswordVisible,
                  onTogglePasswordVisibility: () {
                    setState(() {
                      _isSqlPasswordVisible = !_isSqlPasswordVisible;
                    });
                  },
                  validator: _requiredValidator,
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _saveProfile,
                    icon: Icon(
                      _editingIndex == null
                          ? Icons.add_circle_outline
                          : Icons.save_outlined,
                    ),
                    label: Text(
                      _editingIndex == null ? 'Save Setting' : 'Update Setting',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearForm,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfilesPanel(TextStyle? headline) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isAdmin ? 'Saved Settings' : 'Attach / Detach',
              style: headline,
            ),
            const SizedBox(height: 8),
            Text(
              _isAdmin
                  ? 'These profiles are stored in MySQL and can be used for secure attach and detach operations.'
                  : 'This user view only exposes database operation controls for the saved profiles.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6478)),
            ),
            const SizedBox(height: 20),
            if (_lastMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD8E2EC)),
                ),
                child: Text(
                  _lastMessage!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_isLoadingProfiles)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_profiles.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD8E2EC)),
                ),
                child: Text(
                  'No settings saved yet. Save your first SQL Server configuration and it will be stored in MySQL.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _profiles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final profile = _profiles[index];
                  final isBusy = _busyIndex == index;
                  final isAttached =
                      profile.attachmentStatus ==
                      DatabaseAttachmentStatus.attached;
                  final isDetached =
                      profile.attachmentStatus ==
                      DatabaseAttachmentStatus.detached;
                  final hasNameConflict =
                      profile.attachmentStatus ==
                      DatabaseAttachmentStatus.nameConflict;
                  final gradientColors = isAttached
                      ? const [Color(0xFF17785B), Color(0xFF11493A)]
                      : hasNameConflict
                      ? const [Color(0xFFB45309), Color(0xFF7C2D12)]
                      : const [Color(0xFF0C5E77), Color(0xFF143A52)];

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile.databaseName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Server hidden for security',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 10),
                                  _statusChip(profile.attachmentStatus),
                                ],
                              ),
                            ),
                            if (_isAdmin) ...[
                              IconButton(
                                tooltip: 'Edit setting',
                                onPressed: isBusy
                                    ? null
                                    : () => _loadProfileForEditing(index),
                                color: Colors.white,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete setting',
                                onPressed: isBusy
                                    ? null
                                    : () => _deleteProfile(index),
                                color: Colors.white,
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ],
                        ),
                        if (_isAdmin) ...[
                          const SizedBox(height: 16),
                          _infoLine('MDF', profile.mdfPath),
                          if (profile.ldfPath.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _infoLine('LDF', profile.ldfPath),
                          ],
                          const SizedBox(height: 8),
                          _infoLine(
                            'Auth',
                            profile.authenticationMode ==
                                    AuthenticationMode.windows
                                ? 'Windows Authentication'
                                : 'SQL Server Login (${profile.username})',
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Restricted operations view. Configuration details remain hidden in user mode.',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF0C5E77),
                              ),
                              onPressed: isBusy || isAttached || hasNameConflict
                                  ? null
                                  : () => _attachDatabase(index),
                              icon: isBusy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.link),
                              label: const Text('Attach'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                              ),
                              onPressed: isBusy || isDetached || hasNameConflict
                                  ? null
                                  : () => _detachDatabase(index),
                              icon: const Icon(Icons.link_off),
                              label: const Text('Detach'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    bool obscureText = false,
    bool isPasswordVisible = false,
    VoidCallback? onTogglePasswordVisibility,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText && !isPasswordVisible,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: obscureText
            ? IconButton(
                tooltip: isPasswordVisible ? 'Hide password' : 'Show password',
                onPressed: onTogglePasswordVisibility,
                icon: Icon(
                  isPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _statusChip(DatabaseAttachmentStatus attachmentStatus) {
    final label = switch (attachmentStatus) {
      DatabaseAttachmentStatus.attached => 'Attached',
      DatabaseAttachmentStatus.detached => 'Detached',
      DatabaseAttachmentStatus.nameConflict => 'Name Conflict',
      DatabaseAttachmentStatus.unknown => 'Unknown',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _dialogInfoLine(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _infoLine(String title, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$title: ',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({
    super.key,
    required this.size,
    this.showHalo = false,
    this.compact = false,
  });

  final double size;
  final bool showHalo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.3;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showHalo)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x6633D6C9),
                    blurRadius: size * 0.35,
                    spreadRadius: size * 0.08,
                  ),
                ],
              ),
            ),
          Container(
            width: size * (compact ? 0.9 : 1),
            height: size * (compact ? 0.9 : 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0E7490),
                  Color(0xFF0A2540),
                  Color(0xFFE7A06A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: size * 0.16,
            right: size * 0.12,
            child: Container(
              width: size * 0.18,
              height: size * 0.18,
              decoration: const BoxDecoration(
                color: Color(0xFF33D6C9),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Icon(Icons.storage_rounded, size: size * 0.42, color: Colors.white),
          Positioned(
            bottom: size * 0.12,
            right: size * 0.12,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(size * 0.1),
              ),
              child: Icon(
                Icons.shield_outlined,
                size: size * 0.18,
                color: const Color(0xFF0E7490),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.userType});

  final UserType userType;

  @override
  Widget build(BuildContext context) {
    final isAdmin = userType == UserType.admin;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isAdmin ? const Color(0xFFE8F5F8) : const Color(0xFFFFF2EA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdmin
                ? Icons.admin_panel_settings_outlined
                : Icons.person_outline,
            size: 18,
            color: isAdmin ? const Color(0xFF0E7490) : const Color(0xFFB45309),
          ),
          const SizedBox(width: 8),
          Text(
            isAdmin ? 'Admin' : 'User',
            style: TextStyle(
              color: isAdmin
                  ? const Color(0xFF0E7490)
                  : const Color(0xFFB45309),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecuritySpotlightCard extends StatelessWidget {
  const _SecuritySpotlightCard({
    required this.title,
    required this.description,
    required this.accent,
  });

  final String title;
  final String description;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.verified_user_outlined, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF113247),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4F6478),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
