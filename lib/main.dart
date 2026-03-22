import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api_client.dart';
import 'database_profile.dart';
import 'operation_result.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const DatabaseUtilitiesApp());
}

class DatabaseUtilitiesApp extends StatelessWidget {
  const DatabaseUtilitiesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B5D7A),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Database Utilities',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        useMaterial3: true,
      ),
      home: const LaunchGatePage(),
    );
  }
}

class LaunchGatePage extends StatefulWidget {
  const LaunchGatePage({super.key});

  @override
  State<LaunchGatePage> createState() => _LaunchGatePageState();
}

class _LaunchGatePageState extends State<LaunchGatePage> {
  final _passwordController = TextEditingController();
  String? _errorMessage;

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
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_passwordController.text.trim() != _expectedPassword) {
      setState(() {
        _errorMessage = 'Invalid launch password for today.';
      });
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DatabaseUtilityHomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Launch Security',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0A2540),
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Enter today\'s password in the format `OneNetDDMMMyyyy` to open the app.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF4F6478),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        onSubmitted: (_) => _unlock(),
                        decoration: InputDecoration(
                          labelText: 'Launch password',
                          hintText: 'OneNet21Mar2026',
                          errorText: _errorMessage,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'API: ${dotenv.env['API_BASE_URL'] ?? 'Not configured'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF4F6478),
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _unlock,
                          child: const Text('Unlock'),
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
    );
  }
}

class DatabaseUtilityHomePage extends StatefulWidget {
  const DatabaseUtilityHomePage({super.key});

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
  String? _lastCommand;
  String? _apiStatusMessage;

  String get _apiBaseUrl => dotenv.env['API_BASE_URL'] ?? '';

  ApiClient get _apiClient => ApiClient(baseUrl: _apiBaseUrl);

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
        _lastCommand = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingProfiles = false;
        _apiStatusMessage = null;
        _lastMessage = 'Could not load saved settings. Details: $error';
        _lastCommand = null;
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
    _editingIndex = null;
    setState(() {});
  }

  void _loadProfileForEditing(int index) {
    final profile = _profiles[index];
    _serverController.text = profile.server;
    _databaseNameController.text = profile.databaseName;
    _mdfPathController.text = profile.mdfPath;
    _ldfPathController.text = profile.ldfPath;
    _usernameController.text = profile.username;
    _passwordController.text = profile.password;
    _authenticationMode = profile.authenticationMode;
    _editingIndex = index;
    setState(() {});
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
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
      _lastCommand = null;
    });

    final result = await _apiClient.saveProfile(profile);
    if (!mounted) {
      return;
    }

    setState(() {
      _lastMessage = result.message;
      _lastCommand = result.command;
    });

    if (result.success) {
      _clearForm();
      await _loadProfiles();
      if (!mounted) {
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.success
            ? Colors.green.shade700
            : Colors.red.shade700,
        content: Text(result.message),
      ),
    );
  }

  Future<void> _deleteProfile(int index) async {
    final profile = _profiles[index];
    if (profile.id == null) {
      return;
    }

    setState(() {
      _busyIndex = index;
      _lastMessage = 'Deleting saved setting for ${profile.databaseName}...';
      _lastCommand = null;
    });

    final result = await _apiClient.deleteProfile(profile.id!);
    if (!mounted) {
      return;
    }

    setState(() {
      _busyIndex = null;
      _lastMessage = result.message;
      _lastCommand = result.command;
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
  }

  Future<void> _attachDatabase(int index) async {
    await _runOperation(
      index: index,
      actionLabel: 'attach',
      request: _apiClient.attach,
    );
  }

  Future<void> _detachDatabase(int index) async {
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
      _lastCommand = result.command;
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
    final headline = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: const Color(0xFF0A2540),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Utilities'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Reload settings',
            onPressed: _isLoadingProfiles ? null : _loadProfiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1050;

            final formPanel = _buildFormPanel(headline);
            final listPanel = _buildProfilesPanel(headline);

            return Padding(
              padding: const EdgeInsets.all(20),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: formPanel),
                        const SizedBox(width: 20),
                        Expanded(flex: 6, child: listPanel),
                      ],
                    )
                  : ListView(
                      children: [
                        formPanel,
                        const SizedBox(height: 20),
                        listPanel,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFormPanel(TextStyle? headline) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                'These settings are saved in MySQL through the backend API and loaded again when the app starts.',
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
                      'API base URL from .env',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF355468),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _apiBaseUrl,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
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
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3F8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'First launch is protected with today\'s password in the format OneNetDDMMMyyyy, for example OneNet21Mar2026.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfilesPanel(TextStyle? headline) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saved Settings', style: headline),
            const SizedBox(height: 8),
            Text(
              'These profiles are stored in MySQL and can be used for attach and detach operations.',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastMessage!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_lastCommand != null && _lastCommand!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SelectableText(
                        _lastCommand!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
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
                  final gradientColors = isAttached
                      ? const [Color(0xFF1F9D55), Color(0xFF14532D)]
                      : const [Color(0xFF0E7490), Color(0xFF164E63)];
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
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
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    profile.server,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isAttached
                                          ? Colors.white.withValues(alpha: 0.18)
                                          : Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: isAttached
                                            ? const Color(0xFFBBF7D0)
                                            : Colors.white24,
                                      ),
                                    ),
                                    child: Text(
                                      switch (profile.attachmentStatus) {
                                        DatabaseAttachmentStatus.attached =>
                                          'Attached',
                                        DatabaseAttachmentStatus.detached =>
                                          'Detached',
                                        DatabaseAttachmentStatus.unknown =>
                                          'Unknown',
                                      },
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                        ),
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
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF0E7490),
                              ),
                              onPressed: isBusy || isAttached
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
                              onPressed: isBusy || isDetached
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
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        filled: true,
        fillColor: Colors.white,
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
