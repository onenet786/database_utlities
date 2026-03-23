import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'activity_log_entry.dart';
import 'api_client.dart';
import 'app_session.dart';
import 'app_user.dart';
import 'client_settings.dart';
import 'database_profile.dart';
import 'operation_result.dart';
import 'security_preference.dart';

enum _DetachAction { cancel, detachOnly, backupAndDetach }

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
  static const Duration _sessionInactivityTimeout = Duration(seconds: 30);

  bool _isUnlocked = false;
  bool _isSplashComplete = false;
  AppSession? _currentSession;
  Timer? _splashTimer;
  Timer? _sessionTimeoutTimer;
  DateTime? _lastActivityAt;
  ApiClient get _apiClient =>
      ApiClient(baseUrl: dotenv.env['API_BASE_URL'] ?? '');

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
    _sessionTimeoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isUnlocked) {
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _syncSessionTimeoutWithActivity();
      return;
    }

    if (state == AppLifecycleState.detached) {
      _lockSession(
        actionDetails: 'The workspace session was closed when the app detached.',
      );
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _sessionTimeoutTimer?.cancel();
    }
  }

  void _unlockSession(AppSession session) {
    setState(() {
      _currentSession = session;
      _isUnlocked = true;
    });
    _registerSessionActivity();
  }

  void _registerSessionActivity() {
    if (!_isUnlocked) {
      return;
    }

    _lastActivityAt = DateTime.now();
    _scheduleSessionTimeout(_sessionInactivityTimeout);
  }

  void _scheduleSessionTimeout(Duration timeout) {
    _sessionTimeoutTimer?.cancel();
    if (!_isUnlocked) {
      return;
    }

    _sessionTimeoutTimer = Timer(timeout, () {
      _lockSession(
        actionDetails:
            'The workspace session expired after 30 seconds of inactivity.',
      );
    });
  }

  void _syncSessionTimeoutWithActivity() {
    final lastActivityAt = _lastActivityAt;
    if (!_isUnlocked || lastActivityAt == null) {
      return;
    }

    final elapsed = DateTime.now().difference(lastActivityAt);
    final remaining = _sessionInactivityTimeout - elapsed;
    if (remaining <= Duration.zero) {
      _lockSession(
        actionDetails:
            'The workspace session expired after 30 seconds of inactivity.',
      );
      return;
    }

    _scheduleSessionTimeout(remaining);
  }

  void _lockSession({
    String actionDetails = 'The workspace session was locked.',
  }) {
    if (!_isUnlocked) {
      return;
    }

    _sessionTimeoutTimer?.cancel();

    final session = _currentSession;
    if (session != null) {
      unawaited(
        _apiClient.logActivity(
          clientId: session.clientId,
          actorUsername: session.username,
          actorRole: session.role == UserType.admin ? 'admin' : 'user',
          actionName: 'lock_session',
          actionDetails: actionDetails,
        ),
      );
    }

    setState(() {
      _isUnlocked = false;
      _currentSession = null;
      _lastActivityAt = null;
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
            ? _SessionActivityScope(
                key: const ValueKey('session-home'),
                onActivity: _registerSessionActivity,
                child: DatabaseUtilityHomePage(
                  key: const ValueKey('home'),
                  session: _currentSession!,
                  onLockRequested: _lockSession,
                ),
              )
            : LaunchGatePage(
                key: const ValueKey('launch'),
                onUnlock: _unlockSession,
              ),
      ),
    );
  }
}

class _SessionActivityScope extends StatelessWidget {
  const _SessionActivityScope({
    super.key,
    required this.child,
    required this.onActivity,
  });

  final Widget child;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onActivity(),
      onPointerSignal: (_) => onActivity(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, _) {
          onActivity();
          return KeyEventResult.ignored;
        },
        child: child,
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

  final ValueChanged<AppSession> onUnlock;

  @override
  State<LaunchGatePage> createState() => _LaunchGatePageState();
}

class _LaunchGatePageState extends State<LaunchGatePage> {
  final _usernameController = TextEditingController(text: 'user');
  final _passwordController = TextEditingController();
  final ApiClient _apiClient = ApiClient(
    baseUrl: dotenv.env['API_BASE_URL'] ?? '',
  );

  String? _errorMessage;
  bool _isLaunchPasswordVisible = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Username and password are required.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final session = await _apiClient.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      widget.onUnlock(session);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Sign in failed. Details: $error';
        _isSubmitting = false;
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Secure Sign In',
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
                                    'Use your assigned username and password to open the workspace.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF4F6478),
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7FAFC),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xFFD8E2EC),
                                  ),
                                ),
                                child: const Column(
                                  children: [
                                    AppBrandMark(size: 84, showHalo: true),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: _usernameController,
                                enabled: !_isSubmitting,
                                decoration: InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(18),
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passwordController,
                                obscureText: !_isLaunchPasswordVisible,
                                onSubmitted: (_) =>
                                    _isSubmitting ? null : _unlock(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  errorText: _errorMessage,
                                  prefixIcon: const Icon(
                                    Icons.password_outlined,
                                  ),
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
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _isSubmitting ? null : _unlock,
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
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
              );
            },
          ),
        ),
      ),
    );
  }
}

class DatabaseUtilityHomePage extends StatefulWidget {
  const DatabaseUtilityHomePage({
    super.key,
    required this.session,
    required this.onLockRequested,
  });

  final AppSession session;
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
  bool _isSqlPasswordVisible = false;
  bool _isAppUserPasswordVisible = false;
  bool _isDiscoveringInstances = false;
  bool _isDiscoveringDatabases = false;
  bool _isPickingMdf = false;
  bool _isPickingLdf = false;
  ClientSettings? _clientSettings;
  List<ClientSettings> _clients = [];
  List<AppUser> _users = [];
  List<ActivityLogEntry> _activityLogs = [];
  bool _isLoadingAdminData = false;
  final _companyNameController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _appUsernameController = TextEditingController();
  final _appUserPasswordController = TextEditingController();
  UserType _appUserRole = UserType.user;
  int? _editingClientId;
  int? _selectedClientId;
  int? _editingUserId;
  int? _selectedUserId;
  AdminSection _selectedAdminSection = AdminSection.dashboard;

  ApiClient get _apiClient =>
      ApiClient(baseUrl: dotenv.env['API_BASE_URL'] ?? '');
  bool get _isAdmin => widget.session.role == UserType.admin;
  int get _activeClientId => _isAdmin
      ? (_selectedClientId ?? _clientSettings?.id ?? widget.session.clientId)
      : widget.session.clientId;

  @override
  void initState() {
    super.initState();
    _clientSettings = widget.session.clientSettings;
    _selectedClientId = widget.session.clientId;
    _companyNameController.text = widget.session.clientSettings.companyName;
    _branchNameController.text = widget.session.clientSettings.branchName;
    _loadProfiles();
    if (_isAdmin) {
      _loadAdminData();
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _databaseNameController.dispose();
    _mdfPathController.dispose();
    _ldfPathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _companyNameController.dispose();
    _branchNameController.dispose();
    _appUsernameController.dispose();
    _appUserPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminData() async {
    if (!_isAdmin) {
      return;
    }

    setState(() {
      _isLoadingAdminData = true;
    });

    try {
      final clients = await _apiClient.fetchClientSettingsList();
      final users = await _apiClient.fetchUsers(clientId: _activeClientId);
      final activityLogs = await _apiClient.fetchActivityLogs(
        clientId: _activeClientId,
        limit: 120,
      );
      if (!mounted) {
        return;
      }

      ClientSettings? selectedClient;
      if (_selectedClientId != null) {
        final selectedIndex = clients.indexWhere(
          (client) => client.id == _selectedClientId,
        );
        if (selectedIndex >= 0) {
          selectedClient = clients[selectedIndex];
        }
      }
      final activeClient =
          selectedClient ??
          (clients.isNotEmpty
              ? clients.first
              : const ClientSettings(
                  id: 1,
                  companyName: 'Database Utilities',
                  branchName: 'Main Branch',
                ));

      setState(() {
        _clientSettings = activeClient;
        _clients = clients;
        if (_editingClientId == null) {
          _companyNameController.text = activeClient.companyName;
          _branchNameController.text = activeClient.branchName;
        }
        if (_editingClientId == null) {
          _selectedClientId = activeClient.id;
        } else if (!_clients.any((client) => client.id == _selectedClientId)) {
          _selectedClientId = null;
        }
        _users = users;
        _activityLogs = activityLogs;
        if (_selectedUserId != null &&
            !_users.any((user) => user.id == _selectedUserId)) {
          _selectedUserId = null;
        }
        _isLoadingAdminData = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _lastMessage = 'Could not load admin data. Details: $error';
        _isLoadingAdminData = false;
      });
    }
  }

  Future<void> _saveClientSettings() async {
    if (!_isAdmin) {
      return;
    }

    try {
      final settings = ClientSettings(
        id: _editingClientId,
        companyName: _companyNameController.text.trim(),
        branchName: _branchNameController.text.trim(),
      );
      final savedClient = await _apiClient.saveClientSettings(
        settings: settings,
        actorUsername: widget.session.username,
        actorRole: _roleValue(widget.session.role),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _clientSettings = savedClient;
        _selectedClientId = savedClient.id;
        _editingClientId = null;
        _lastMessage = settings.id == null
            ? 'Client added successfully.'
            : 'Client settings saved successfully.';
      });
      await _loadAdminData();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastMessage = 'Could not save client settings. Details: $error';
      });
    }
  }

  void _loadClientForEditing(ClientSettings client) {
    _editingClientId = client.id;
    _selectedClientId = client.id;
    _companyNameController.text = client.companyName;
    _branchNameController.text = client.branchName;
    setState(() {});
  }

  void _clearClientForm() {
    _editingClientId = null;
    _selectedClientId = null;
    _companyNameController.clear();
    _branchNameController.clear();
    setState(() {});
  }

  void _loadUserForEditing(AppUser user) {
    _editingUserId = user.id;
    _selectedUserId = user.id;
    _appUsernameController.text = user.username;
    _appUserPasswordController.clear();
    _appUserRole = user.role;
    _isAppUserPasswordVisible = false;
    setState(() {});
  }

  void _clearUserForm() {
    _editingUserId = null;
    _selectedUserId = null;
    _appUsernameController.clear();
    _appUserPasswordController.clear();
    _appUserRole = UserType.user;
    _isAppUserPasswordVisible = false;
    setState(() {});
  }

  Future<void> _saveAppUser() async {
    if (!_isAdmin) {
      return;
    }

    final result = await _apiClient.saveUser(
      user: AppUser(
        id: _editingUserId,
        username: _appUsernameController.text.trim(),
        password: _appUserPasswordController.text,
        role: _appUserRole,
      ),
      clientId: _activeClientId,
      actorUsername: widget.session.username,
      actorRole: _roleValue(widget.session.role),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _lastMessage = result.message;
    });
    if (result.success) {
      _clearUserForm();
      await _loadAdminData();
    }
    _showOperationSnackBar(result);
  }

  Future<void> _deleteAppUser(AppUser user) async {
    if (!_isAdmin || user.id == null) {
      return;
    }

    final result = await _apiClient.deleteUser(
      user.id!,
      clientId: _activeClientId,
      actorUsername: widget.session.username,
      actorRole: _roleValue(widget.session.role),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _lastMessage = result.message;
    });
    if (result.success) {
      await _loadAdminData();
    }
    _showOperationSnackBar(result);
  }

  String _roleValue(UserType role) => role == UserType.admin ? 'admin' : 'user';

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoadingProfiles = true;
    });

    try {
      final profiles = await _apiClient.fetchProfiles(
        clientId: _activeClientId,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _profiles = profiles;
        _isLoadingProfiles = false;
        _lastMessage = profiles.isEmpty
            ? 'Load 0 settings from server.'
            : 'Load ${profiles.length} settings from server.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingProfiles = false;
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
      clientId: _activeClientId,
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

    final result = await _apiClient.saveProfile(
      profile,
      clientId: _activeClientId,
      actorUsername: widget.session.username,
      actorRole: _roleValue(widget.session.role),
    );
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

    final result = await _apiClient.deleteProfile(
      profile.id!,
      clientId: _activeClientId,
      actorUsername: widget.session.username,
      actorRole: _roleValue(widget.session.role),
    );
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

  String _buildBackupPath(DatabaseProfile profile) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final normalizedPath = profile.mdfPath.replaceAll('/', r'\');
    final separatorIndex = normalizedPath.lastIndexOf(r'\');
    final baseDir = separatorIndex >= 0
        ? normalizedPath.substring(0, separatorIndex)
        : normalizedPath;
    return '$baseDir\\${profile.databaseName}_$timestamp.bak';
  }

  Future<OperationResult> _runBackupOnly(
    DatabaseProfile profile, {
    required String backupPath,
  }) {
    return _apiClient.backupDatabase(
      profile,
      backupPath: backupPath,
      actorUsername: widget.session.username,
      actorRole: _roleValue(widget.session.role),
    );
  }

  Future<void> _backupDatabase(int index) async {
    final profile = _profiles[index];
    final backupPath = _buildBackupPath(profile);
    final shouldBackup = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create a backup for ${profile.databaseName} before any change?',
              ),
              const SizedBox(height: 12),
              _dialogInfoLine('Backup file', backupPath),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Backup'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldBackup != true) {
      return;
    }

    setState(() {
      _busyIndex = index;
      _lastMessage = 'Creating backup for ${profile.databaseName}...';
    });

    final result = await _runBackupOnly(profile, backupPath: backupPath);
    if (!mounted) {
      return;
    }

    setState(() {
      _busyIndex = null;
      _lastMessage = result.message;
    });

    _showOperationSnackBar(result);
  }

  Future<void> _browseSqlInstances() async {
    if (_isDiscoveringInstances) {
      return;
    }

    setState(() {
      _isDiscoveringInstances = true;
    });

    try {
      final instances = await _apiClient.discoverSqlInstances();
      if (!mounted) {
        return;
      }

      final selection = await _showStringSelectionDialog(
        title: 'SQL Server Instances',
        items: instances,
        emptyMessage: 'No SQL Server instances were discovered.',
      );
      if (!mounted || selection == null) {
        return;
      }

      setState(() {
        _serverController.text = selection;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showOperationSnackBar(
        OperationResult(success: false, message: '$error', command: ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDiscoveringInstances = false;
        });
      }
    }
  }

  Future<void> _browseDatabases() async {
    if (_isDiscoveringDatabases) {
      return;
    }

    final server = _serverController.text.trim();
    if (server.isEmpty) {
      _showOperationSnackBar(
        const OperationResult(
          success: false,
          message: 'Enter or browse a SQL Server instance first.',
          command: '',
        ),
      );
      return;
    }

    setState(() {
      _isDiscoveringDatabases = true;
    });

    try {
      final databases = await _apiClient.discoverDatabases(
        server: server,
        authenticationMode: _authenticationMode,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }

      final selection = await _showStringSelectionDialog(
        title: 'Databases',
        items: databases,
        emptyMessage: 'No databases were returned by SQL Server.',
      );
      if (!mounted || selection == null) {
        return;
      }

      setState(() {
        _databaseNameController.text = selection;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showOperationSnackBar(
        OperationResult(success: false, message: '$error', command: ''),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDiscoveringDatabases = false;
        });
      }
    }
  }

  Future<void> _pickMdfFile() async {
    if (_isPickingMdf) {
      return;
    }

    setState(() {
      _isPickingMdf = true;
    });

    try {
      const typeGroup = XTypeGroup(label: 'MDF files', extensions: ['mdf']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (!mounted || file == null) {
        return;
      }

      final path = _resolvedLocalFilePath(file);
      final fileName = file.name;
      final dotIndex = fileName.lastIndexOf('.');
      final guessedName = dotIndex > 0
          ? fileName.substring(0, dotIndex)
          : fileName;

      if (path == null) {
        if (_databaseNameController.text.trim().isEmpty) {
          setState(() {
            _databaseNameController.text = guessedName;
          });
        }
        _showBrowserPathLimitationMessage(fileLabel: 'MDF');
        return;
      }

      setState(() {
        _mdfPathController.text = path;
        if (_databaseNameController.text.trim().isEmpty) {
          _databaseNameController.text = guessedName;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showOperationSnackBar(
        OperationResult(
          success: false,
          message: 'Could not browse MDF file. Details: $error',
          command: '',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingMdf = false;
        });
      }
    }
  }

  Future<void> _pickLdfFile() async {
    if (_isPickingLdf) {
      return;
    }

    setState(() {
      _isPickingLdf = true;
    });

    try {
      const typeGroup = XTypeGroup(label: 'LDF files', extensions: ['ldf']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (!mounted || file == null) {
        return;
      }

      final path = _resolvedLocalFilePath(file);
      if (path == null) {
        _showBrowserPathLimitationMessage(fileLabel: 'LDF');
        return;
      }

      setState(() {
        _ldfPathController.text = path;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showOperationSnackBar(
        OperationResult(
          success: false,
          message: 'Could not browse LDF file. Details: $error',
          command: '',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingLdf = false;
        });
      }
    }
  }

  Future<String?> _showStringSelectionDialog({
    required String title,
    required List<String> items,
    required String emptyMessage,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: items.isEmpty
                ? Text(emptyMessage)
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        title: Text(item),
                        onTap: () => Navigator.of(dialogContext).pop(item),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
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

    if (!mounted) {
      return;
    }

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
      request: (profile) => _apiClient.attach(
        profile,
        actorUsername: widget.session.username,
        actorRole: _roleValue(widget.session.role),
      ),
    );
  }

  Future<void> _detachDatabase(int index) async {
    final profile = _profiles[index];
    final backupPath = _buildBackupPath(profile);
    final detachAction = await showDialog<_DetachAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Detach'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detaching ${profile.databaseName} will disconnect active users and rollback uncommitted transactions.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Recommended backup file:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(backupPath),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_DetachAction.cancel),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_DetachAction.detachOnly),
              child: const Text('Detach Only'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_DetachAction.backupAndDetach),
              child: const Text('Backup & Detach'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (detachAction == null || detachAction == _DetachAction.cancel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blueGrey.shade700,
          content: Text('Detach cancelled for ${profile.databaseName}.'),
        ),
      );
      return;
    }

    if (detachAction == _DetachAction.backupAndDetach) {
      setState(() {
        _busyIndex = index;
        _lastMessage = 'Creating backup for ${profile.databaseName}...';
      });
      final backupResult = await _runBackupOnly(
        profile,
        backupPath: backupPath,
      );
      if (!mounted) {
        return;
      }
      if (!backupResult.success) {
        setState(() {
          _busyIndex = null;
          _lastMessage = backupResult.message;
        });
        _showOperationSnackBar(backupResult);
        return;
      }
      setState(() {
        _busyIndex = null;
        _lastMessage = backupResult.message;
      });
      _showOperationSnackBar(backupResult);
    }

    await _runOperation(
      index: index,
      actionLabel: 'detach',
      request: (profile) => _apiClient.detach(
        profile,
        actorUsername: widget.session.username,
        actorRole: _roleValue(widget.session.role),
      ),
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
        final profiles = await _apiClient.fetchProfiles(
          clientId: _activeClientId,
        );
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

  String? _resolvedLocalFilePath(XFile file) {
    final rawPath = file.path.trim();
    if (rawPath.isEmpty) {
      return null;
    }

    if (kIsWeb && rawPath.startsWith('blob:')) {
      return null;
    }

    return rawPath;
  }

  void _showBrowserPathLimitationMessage({required String fileLabel}) {
    _showOperationSnackBar(
      OperationResult(
        success: false,
        message:
            '$fileLabel browse is running in a browser, so only a temporary blob URL is available. Enter the full local Windows path manually, or run the Windows app to browse real file paths.',
        command: '',
      ),
    );
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

  Future<void> _switchAdminClient(int? clientId) async {
    if (!_isAdmin || clientId == null || clientId == _selectedClientId) {
      return;
    }

    final selectedClient = _clients.where((client) => client.id == clientId);
    if (selectedClient.isEmpty) {
      return;
    }

    setState(() {
      _selectedClientId = clientId;
      _clientSettings = selectedClient.first;
      _editingClientId = null;
      _editingUserId = null;
      _selectedUserId = null;
      _editingIndex = null;
      _companyNameController.text = selectedClient.first.companyName;
      _branchNameController.text = selectedClient.first.branchName;
    });

    _clearForm();
    _clearUserForm();
    await _loadProfiles();
    await _loadAdminData();
  }

  @override
  Widget build(BuildContext context) {
    final content = _isAdmin
        ? _buildAdminWorkspace(context)
        : _buildUserWorkspace(context);
    final clientDropdownValue =
        _clients.any(
          (client) => client.id == (_selectedClientId ?? _clientSettings?.id),
        )
        ? (_selectedClientId ?? _clientSettings?.id)
        : null;

    return Scaffold(
      drawer: _isAdmin ? _buildAdminDrawer(context) : null,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Row(
          children: [
            const AppBrandMark(size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Database Utilities',
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_clientSettings?.companyName ?? 'Database Utilities'} • ${_clientSettings?.branchName ?? 'Main Branch'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF4F6478),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_isAdmin && _clients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: clientDropdownValue,
                      borderRadius: BorderRadius.circular(16),
                      isDense: true,
                      isExpanded: true,
                      onChanged: _switchAdminClient,
                      selectedItemBuilder: (context) => _clients
                          .map(
                            (client) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${client.companyName} / ${client.branchName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      items: _clients
                          .map(
                            (client) => DropdownMenuItem<int>(
                              value: client.id,
                              child: Text(
                                '${client.companyName} / ${client.branchName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: _RoleBadge(userType: widget.session.role)),
          ),
          IconButton(
            tooltip: 'Reload settings',
            onPressed: _isLoadingProfiles ? null : _loadProfiles,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Lock workspace',
            onPressed: widget.onLockRequested,
            visualDensity: VisualDensity.compact,
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

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildWorkspaceIntro(title: _selectedAdminSection.title),
        const SizedBox(height: 20),
        _buildAdminSectionContent(headline),
      ],
    );
  }

  Widget _buildUserWorkspace(BuildContext context) {
    final headline = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF0A2540),
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [_buildProfilesPanel(headline)],
    );
  }

  Widget _buildWorkspaceIntro({required String title}) {
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminDrawer(BuildContext context) {
    final sections = AdminSection.values;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0E3B4D),
                      Color(0xFF0E7490),
                      Color(0xFFE7A06A),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        AppBrandMark(size: 42, compact: true),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Admin Workspace',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _clientSettings?.companyName ?? 'Database Utilities',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _clientSettings?.branchName ?? 'Main Branch',
                      style: const TextStyle(color: Color(0xFFE6F3F6)),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final section in sections)
                    _buildAdminDrawerTile(
                      context: context,
                      section: section,
                      selected: _selectedAdminSection == section,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminDrawerTile({
    required BuildContext context,
    required AdminSection section,
    required bool selected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(section.icon),
        title: Text(section.label),
        selected: selected,
        selectedTileColor: const Color(0xFFE7F4F7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onTap: () {
          setState(() {
            _selectedAdminSection = section;
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _buildAdminSectionContent(TextStyle? headline) {
    return switch (_selectedAdminSection) {
      AdminSection.dashboard => _buildAdminDashboardPanel(headline),
      AdminSection.databaseProfiles => _buildAdminDatabaseWorkspace(headline),
      AdminSection.clientSettings => _buildClientPanel(headline),
      AdminSection.userManagement => _buildUserPanel(headline),
      AdminSection.activityLogs => _buildActivityPanel(headline),
    };
  }

  Widget _buildAdminDashboardPanel(TextStyle? headline) {
    final attachedCount = _profiles
        .where(
          (profile) =>
              profile.attachmentStatus == DatabaseAttachmentStatus.attached,
        )
        .length;
    final detachedCount = _profiles
        .where(
          (profile) =>
              profile.attachmentStatus == DatabaseAttachmentStatus.detached,
        )
        .length;
    final adminCount = _users
        .where((user) => user.role == UserType.admin)
        .length;
    final userCount = _users.where((user) => user.role == UserType.user).length;

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Operations Overview', style: headline),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildDashboardStatCard(
                      title: 'Saved Databases',
                      value: '${_profiles.length}',
                      subtitle:
                          '$attachedCount attached, $detachedCount detached',
                      icon: Icons.storage_rounded,
                    ),
                    _buildDashboardStatCard(
                      title: 'Users',
                      value: '${_users.length}',
                      subtitle: '$adminCount admins, $userCount operators',
                      icon: Icons.groups_2_outlined,
                    ),
                    _buildDashboardStatCard(
                      title: 'Activity Logs',
                      value: '${_activityLogs.length}',
                      subtitle:
                          'Latest ${_activityLogs.length.clamp(0, 120)} loaded',
                      icon: Icons.history_rounded,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminDatabaseWorkspace(TextStyle? headline) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        final formPanel = _buildFormPanel(headline);
        final listPanel = _buildProfilesPanel(headline);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: formPanel),
              const SizedBox(width: 20),
              Expanded(flex: 6, child: listPanel),
            ],
          );
        }

        return Column(
          children: [formPanel, const SizedBox(height: 20), listPanel],
        );
      },
    );
  }

  Widget _buildDashboardStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD8E2EC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFE7F4F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF0E7490)),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0A2540),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF113247),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF4F6478)),
            ),
          ],
        ),
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
              const SizedBox(height: 20),
              _buildField(
                controller: _serverController,
                label: 'SQL Server instance',
                hint: r'.\SQLEXPRESS or localhost',
                validator: _requiredValidator,
                trailingAction: TextButton.icon(
                  onPressed: _isDiscoveringInstances
                      ? null
                      : _browseSqlInstances,
                  icon: _isDiscoveringInstances
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore_outlined),
                  label: const Text('Browse'),
                ),
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _databaseNameController,
                label: 'Database name',
                hint: 'EmployeeDB',
                validator: _requiredValidator,
                trailingAction: TextButton.icon(
                  onPressed: _isDiscoveringDatabases ? null : _browseDatabases,
                  icon: _isDiscoveringDatabases
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_outlined),
                  label: const Text('Browse'),
                ),
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _mdfPathController,
                label: 'MDF file path',
                hint: r'C:\SQLData\EmployeeDB.mdf',
                validator: _requiredValidator,
                trailingAction: TextButton.icon(
                  onPressed: _isPickingMdf ? null : _pickMdfFile,
                  icon: _isPickingMdf
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: const Text('Browse'),
                ),
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _ldfPathController,
                label: 'LDF file path',
                hint: r'C:\SQLData\EmployeeDB_log.ldf (optional)',
                trailingAction: TextButton.icon(
                  onPressed: _isPickingLdf ? null : _pickLdfFile,
                  icon: _isPickingLdf
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: const Text('Browse'),
                ),
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
                  hint: '',
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

  Widget _buildClientPanel(TextStyle? headline) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Client Settings', style: headline),
            const SizedBox(height: 20),
            _buildField(
              controller: _companyNameController,
              label: 'Company name',
              hint: 'Acme Corporation',
              validator: _requiredValidator,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _branchNameController,
              label: 'Branch name',
              hint: 'Lahore Branch',
              validator: _requiredValidator,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _saveClientSettings,
                  icon: const Icon(Icons.apartment_outlined),
                  label: Text(
                    _editingClientId == null ? 'Add Client' : 'Update Client',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _clearClientForm,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('New Client'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoadingAdminData)
              const Center(child: CircularProgressIndicator())
            else
              _buildClientsTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildClientsTable() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFD8E2EC)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 640),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFE7F4F7)),
              columns: const [
                DataColumn(label: Text('Company')),
                DataColumn(label: Text('Branch')),
                DataColumn(label: Text('Edit')),
              ],
              rows: _clients.map((client) {
                final isSelected =
                    _selectedClientId != null &&
                    _selectedClientId == (client.id ?? -1);
                return DataRow(
                  selected: isSelected,
                  onSelectChanged: (_) {
                    setState(() {
                      _selectedClientId = client.id;
                    });
                  },
                  cells: [
                    DataCell(
                      Text(client.companyName),
                      onDoubleTap: () => _loadClientForEditing(client),
                    ),
                    DataCell(
                      Text(client.branchName),
                      onDoubleTap: () => _loadClientForEditing(client),
                    ),
                    DataCell(
                      IconButton(
                        tooltip: 'Edit client',
                        onPressed: () => _loadClientForEditing(client),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      onDoubleTap: () => _loadClientForEditing(client),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserPanel(TextStyle? headline) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Users & Roles', style: headline),
            const SizedBox(height: 20),
            _buildField(
              controller: _appUsernameController,
              label: 'Username',
              hint: 'operator01',
              validator: _requiredValidator,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _appUserPasswordController,
              label: _editingUserId == null ? 'Password' : 'New password',
              hint: '',
              obscureText: true,
              isPasswordVisible: _isAppUserPasswordVisible,
              onTogglePasswordVisibility: () {
                setState(() {
                  _isAppUserPasswordVisible = !_isAppUserPasswordVisible;
                });
              },
            ),
            const SizedBox(height: 16),
            SegmentedButton<UserType>(
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
              selected: {_appUserRole},
              onSelectionChanged: (selection) {
                setState(() {
                  _appUserRole = selection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _saveAppUser,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    _editingUserId == null ? 'Save User' : 'Update User',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _clearUserForm,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoadingAdminData)
              const Center(child: CircularProgressIndicator())
            else
              _buildUsersTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityPanel(TextStyle? headline) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity Logs', style: headline),
            const SizedBox(height: 20),
            if (_isLoadingAdminData)
              const Center(child: CircularProgressIndicator())
            else if (_activityLogs.isEmpty)
              const Text('No activity logs recorded yet.')
            else
              _buildActivityLogsTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTable() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFD8E2EC)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 640),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFE7F4F7)),
              columns: const [
                DataColumn(label: Text('Username')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Edit')),
                DataColumn(label: Text('Delete')),
              ],
              rows: _users.map((user) {
                final isSelected =
                    _selectedUserId != null &&
                    _selectedUserId == (user.id ?? -1);
                return DataRow(
                  selected: isSelected,
                  onSelectChanged: (_) {
                    setState(() {
                      _selectedUserId = user.id;
                    });
                  },
                  cells: [
                    DataCell(
                      Text(user.username),
                      onDoubleTap: () => _loadUserForEditing(user),
                    ),
                    DataCell(
                      Text(_roleValue(user.role)),
                      onDoubleTap: () => _loadUserForEditing(user),
                    ),
                    DataCell(
                      IconButton(
                        tooltip: 'Edit user',
                        onPressed: () => _loadUserForEditing(user),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      onDoubleTap: () => _loadUserForEditing(user),
                    ),
                    DataCell(
                      IconButton(
                        tooltip: 'Delete user',
                        onPressed: user.id == null
                            ? null
                            : () => _deleteAppUser(user),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityLogsTable() {
    final logs = _activityLogs.take(40).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFD8E2EC)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 980),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFE7F4F7)),
              columns: const [
                DataColumn(label: Text('User')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Action')),
                DataColumn(label: Text('Details')),
                DataColumn(label: Text('Created')),
              ],
              rows: logs.map((log) {
                return DataRow(
                  cells: [
                    DataCell(Text(log.actorUsername)),
                    DataCell(Text(log.actorRole)),
                    DataCell(Text(log.actionName)),
                    DataCell(
                      SizedBox(
                        width: 360,
                        child: Text(
                          log.actionDetails,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(log.createdAt)),
                  ],
                );
              }).toList(),
            ),
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
              _isAdmin ? 'Saved Settings' : 'Saved Databases',
              style: headline,
            ),
            if (_isAdmin) ...[
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 12),
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
                              onPressed: isBusy || hasNameConflict
                                  ? null
                                  : () => _backupDatabase(index),
                              icon: const Icon(Icons.save_alt_outlined),
                              label: const Text('Backup'),
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
    Widget? trailingAction,
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
            : trailingAction,
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

enum AdminSection {
  dashboard(
    label: 'Dashboard',
    title: 'Admin Dashboard',
    icon: Icons.dashboard_outlined,
  ),
  databaseProfiles(
    label: 'Database Utilities',
    title: 'Database Utilities',
    icon: Icons.storage_rounded,
  ),
  clientSettings(
    label: 'Client Settings',
    title: 'Client Settings',
    icon: Icons.apartment_outlined,
  ),
  userManagement(
    label: 'Users & Roles',
    title: 'Users and Roles',
    icon: Icons.manage_accounts_outlined,
  ),
  activityLogs(
    label: 'Activity Logs',
    title: 'Activity Logs',
    icon: Icons.history_rounded,
  );

  const AdminSection({
    required this.label,
    required this.title,
    required this.icon,
  });

  final String label;
  final String title;
  final IconData icon;
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
