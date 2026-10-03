import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zhirox/services/hikvision_admin_service.dart';

class HikvisionSettingsScreen extends StatefulWidget {
  const HikvisionSettingsScreen({super.key});

  @override
  State<HikvisionSettingsScreen> createState() =>
      _HikvisionSettingsScreenState();
}

class _HikvisionSettingsScreenState extends State<HikvisionSettingsScreen> {
  static const Map<String, String> _cloudServers = {
    'Europe / EMEA': 'https://ieu.hikcentralconnect.com',
    'Singapore / India': 'https://isgp.hikcentralconnect.com',
    'North America': 'https://ius.hikcentralconnect.com',
    'South America': 'https://isa.hikcentralconnect.com',
    'Russia': 'https://hikcentralconnectru.com',
  };

  HikvisionAdminState? _state;
  bool _loading = true;
  bool _working = false;
  String? _error;
  bool _enabled = true;
  bool _autoCapture = true;
  int _channel = 1;
  int _pre = 15;
  int _post = 30;
  int _retention = 90;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<int> _optionsWithCurrent(
    int current,
    Iterable<int> presets, {
    required int min,
    required int max,
  }) {
    final values = <int>{
      for (final value in presets)
        if (value >= min && value <= max) value,
    };
    if (current >= min && current <= max) values.add(current);
    final result = values.toList()..sort();
    return result;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final state = await HikvisionAdminService.status();
      final config = state.config;
      if (!mounted) return;
      setState(() {
        _state = state;
        if (config != null) {
          _enabled = config.enabled;
          _autoCapture = config.autoCapture;
          _channel = config.cashierChannelId.clamp(1, 256);
          _pre = config.preSeconds.clamp(0, 300);
          _post = config.postSeconds.clamp(1, 600);
          _retention = config.retentionDays.clamp(1, 3650);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await HikvisionAdminService.updateConfig(
        enabled: _enabled,
        autoCapture: _autoCapture,
        cashierChannelId: _channel,
        preSeconds: _pre,
        postSeconds: _post,
        retentionDays: _retention,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ڕێکخستنی Hikvision پاشەکەوت کرا ✅')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _connectCloud() async {
    if (_working) return;
    final current = _state?.config?.hikconnectServerAddress ?? '';
    final initialServer = _cloudServers.values.contains(current) ? current : null;
    final appKeyController = TextEditingController();
    final secretKeyController = TextEditingController();
    String? selectedServer = initialServer;

    final input = await showDialog<_CloudCredentialInput>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('پەیوەستکردنی Hik-Connect Cloud'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'هیچ PC یان Gateway ـێک لە مارکێت پێویست نییە. App Key و Secret Key تەنها بۆ backend دەنێردرێن و لە Supabase Vault پارێزراو دەبن.',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedServer,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'ناوچە / سێرڤەری Hik-Connect Team',
                      helperText: 'هەمان ناوچەی Team / API Integration هەڵبژێرە',
                    ),
                    items: _cloudServers.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.value,
                            child: Text(entry.key),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedServer = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: appKeyController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'App Key (AK)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secretKeyController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Secret Key (SK)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'AK/SK لەم شاشەیەوە داخڵ بکە؛ لە چات یان screenshot ـدا مەینێرە.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('پاشگەزبوونەوە'),
            ),
            FilledButton(
              onPressed: () {
                final server = selectedServer;
                final appKey = appKeyController.text.trim();
                final secretKey = secretKeyController.text.trim();
                if (server == null || appKey.length < 8 || secretKey.length < 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('سێرڤەر، App Key و Secret Key پڕ بکەرەوە.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _CloudCredentialInput(
                    serverAddress: server,
                    appKey: appKey,
                    secretKey: secretKey,
                  ),
                );
              },
              child: const Text('پەیوەستکردن'),
            ),
          ],
        ),
      ),
    );

    appKeyController.dispose();
    secretKeyController.dispose();
    if (input == null || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await HikvisionAdminService.saveCloudCredentials(
        serverAddress: input.serverAddress,
        appKey: input.appKey,
        secretKey: input.secretKey,
      );
      final cameras = await HikvisionAdminService.cloudCameras();
      if (!mounted) return;
      final camera = await _pickCamera(cameras);
      if (camera == null || !mounted) {
        await _load();
        return;
      }
      await HikvisionAdminService.selectCloudCamera(camera.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hik-Connect Cloud چالاک کرا ✅  •  ${camera.name.isEmpty ? 'Channel ${camera.channelNo}' : camera.name}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changeCloudCamera() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final cameras = await HikvisionAdminService.cloudCameras();
      if (!mounted) return;
      final camera = await _pickCamera(cameras);
      if (camera == null || !mounted) return;
      await HikvisionAdminService.selectCloudCamera(camera.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<HikvisionCloudCamera?> _pickCamera(
    List<HikvisionCloudCamera> cameras,
  ) async {
    if (cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('هیچ کامێرایەک لە Hik-Connect Team نەدۆزرایەوە.'),
          ),
        );
      }
      return null;
    }

    return showDialog<HikvisionCloudCamera>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('کامێرای کاشێر هەڵبژێرە'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView.separated(
            itemCount: cameras.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final camera = cameras[index];
              return ListTile(
                leading: Icon(
                  camera.online
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  color: camera.online ? Colors.green : null,
                ),
                title: Text(
                  camera.name.isEmpty
                      ? 'Channel ${camera.channelNo}'
                      : camera.name,
                ),
                subtitle: Text(
                  'Channel ${camera.channelNo} • ${camera.online ? 'Online' : 'Offline'}',
                ),
                trailing: camera.channelNo == 1
                    ? const Chip(label: Text('Camera 01'))
                    : null,
                onTap: () => Navigator.pop(dialogContext, camera),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('پاشگەزبوونەوە'),
          ),
        ],
      ),
    );
  }

  Future<void> _useLocalFallback() async {
    if (_working) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('گۆڕین بۆ Local Gateway'),
            content: const Text(
              'ئەمە تەنها fallback ـە و پێویستی بە کۆمپیوتەر/ئامێرێکی هەمیشە چالاک لە مارکێت هەیە. Cloud ـەکە ناچالاک دەبێت بۆ مامەلە نوێکان.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('پاشگەزبوونەوە'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('گۆڕین'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => _working = true);
    try {
      await HikvisionAdminService.useLocalGateway();
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = HikvisionAdminService.userMessage(error));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _issueToken() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final token = await HikvisionAdminService.issueGatewayToken();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Gateway Token — تەنها یەکجار'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ئەم token ـە تەنها بۆ fallback ـی Local Gateway ـە. لە cloud تەنها SHA-256 ـی هەڵدەگیرێت.',
                ),
                const SizedBox(height: 14),
                SelectableText(
                  token,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Token کۆپی کرا')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('کۆپی'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('تەواو'),
            ),
          ],
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = HikvisionAdminService.userMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _date(DateTime? value) {
    if (value == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final config = _state?.config;
    final gateway = _state?.gateway;
    final cloud = _state?.cloud;
    final cloudMode = config?.usesCloud == true;
    final cloudReady = cloudMode &&
        cloud?.healthy == true &&
        (config?.hikconnectCameraId.isNotEmpty ?? false);
    final preOptions = _optionsWithCurrent(
      _pre,
      const [0, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300],
      min: 0,
      max: 300,
    );
    final postOptions = _optionsWithCurrent(
      _post,
      const [1, 5, 10, 15, 30, 45, 60, 90, 120, 180, 300, 600],
      min: 1,
      max: 600,
    );
    final retentionOptions = _optionsWithCurrent(
      _retention,
      const [1, 7, 14, 30, 60, 90, 180, 365, 730, 1825, 3650],
      min: 1,
      max: 3650,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Hikvision و ڤیدیۆی مامەلە')),
      body: _loading && _state == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _CloudStatusCard(
                    cloudMode: cloudMode,
                    ready: cloudReady,
                    configured: cloud?.configured == true,
                    cameraName: config?.hikconnectCameraName ?? '',
                    channel: config?.cashierChannelId ?? 1,
                    lastTest: _date(cloud?.lastTestAt),
                    queued: gateway?.queued ?? 0,
                    processing: gateway?.processing ?? 0,
                    readyCount: gateway?.ready ?? 0,
                    failed: gateway?.failed ?? 0,
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Hik-Connect Cloud',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ڕێگای سەرەکی: iPhone → ZHIROX → Hik-Connect Cloud → NVR. هیچ PC، Raspberry Pi یان Port Forwarding لە مارکێت پێویست نییە.',
                          ),
                          const SizedBox(height: 14),
                          _Info(
                            'دۆخی Cloud',
                            cloud?.configured == true
                                ? (cloudReady ? 'چالاک ✅' : 'پەیوەستە')
                                : 'هێشتا پەیوەست نییە',
                          ),
                          _Info(
                            'کامێرای کاشێر',
                            (config?.hikconnectCameraName.isNotEmpty ?? false)
                                ? config!.hikconnectCameraName
                                : '—',
                          ),
                          _Info(
                            'Channel',
                            (config?.hikconnectCameraId.isNotEmpty ?? false)
                                ? '${config!.cashierChannelId}'
                                : '—',
                          ),
                          _Info('کۆتا تاقیکردنەوە', _date(cloud?.lastTestAt)),
                          if (cloud?.lastError?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Cloud: ${cloud!.lastError}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _working ? null : _connectCloud,
                            icon: const Icon(Icons.cloud_done_rounded),
                            label: Text(
                              cloud?.configured == true
                                  ? 'نوێکردنەوەی پەیوەندی Cloud'
                                  : 'پەیوەستکردنی Hik-Connect Cloud',
                            ),
                          ),
                          if (cloud?.configured == true) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _working ? null : _changeCloudCamera,
                              icon: const Icon(Icons.videocam_rounded),
                              label: const Text('هەڵبژاردن / گۆڕینی کامێرای کاشێر'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'ڕێکخستنی ڤیدیۆی مامەلە',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          _Info('مۆدێلی NVR', config?.nvrModel ?? '—'),
                          _Info('Firmware', config?.nvrFirmware ?? '—'),
                          _Info('Timezone', config?.timezone ?? 'Asia/Baghdad'),
                          const Divider(height: 26),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _enabled,
                            onChanged: _working
                                ? null
                                : (value) => setState(() => _enabled = value),
                            title: const Text('چالاککردنی Hikvision'),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _autoCapture,
                            onChanged: _working
                                ? null
                                : (value) =>
                                    setState(() => _autoCapture = value),
                            title: const Text('بەستنی خۆکاری ڤیدیۆ بە مامەلە'),
                          ),
                          if (!cloudMode) ...[
                            DropdownButtonFormField<int>(
                              initialValue: _channel,
                              isExpanded: true,
                              menuMaxHeight: 420,
                              decoration: const InputDecoration(
                                labelText: 'کامێرای کاشێر',
                              ),
                              items: [
                                for (var channel = 1;
                                    channel <= 256;
                                    channel++)
                                  DropdownMenuItem<int>(
                                    value: channel,
                                    child: Text('Channel $channel'),
                                  ),
                              ],
                              onChanged: _working
                                  ? null
                                  : (value) => setState(
                                        () => _channel = value ?? 1,
                                      ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: _pre,
                                  decoration: const InputDecoration(
                                    labelText: 'پێش مامەلە',
                                  ),
                                  items: preOptions
                                      .map(
                                        (value) => DropdownMenuItem<int>(
                                          value: value,
                                          child: Text('$value چرکە'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _working
                                      ? null
                                      : (value) => setState(
                                            () => _pre = value ?? 15,
                                          ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: _post,
                                  decoration: const InputDecoration(
                                    labelText: 'دوای مامەلە',
                                  ),
                                  items: postOptions
                                      .map(
                                        (value) => DropdownMenuItem<int>(
                                          value: value,
                                          child: Text('$value چرکە'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _working
                                      ? null
                                      : (value) => setState(
                                            () => _post = value ?? 30,
                                          ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: _retention,
                            decoration: const InputDecoration(
                              labelText: 'ماوەی هەڵگرتنی ڤیدیۆ',
                            ),
                            items: retentionOptions
                                .map(
                                  (value) => DropdownMenuItem<int>(
                                    value: value,
                                    child: Text('$value ڕۆژ'),
                                  ),
                                )
                                .toList(),
                            onChanged: _working
                                ? null
                                : (value) => setState(
                                      () => _retention = value ?? 90,
                                    ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _working ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('پاشەکەوتکردنی ڕێکخستن'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: ExpansionTile(
                      title: const Text(
                        'Fallback / Local Gateway',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'تەنها ئەگەر Hik-Connect Cloud بەردەست نەبێت',
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        const Text(
                          'ئەم ڕێگایە پێویستی بە ئامێرێکی هەمیشە چالاک لە تۆڕی مارکێت هەیە. بۆ بەکارهێنانی ئاسایی تۆ Cloud هەڵبژێرە.',
                        ),
                        const SizedBox(height: 12),
                        if (cloudMode)
                          OutlinedButton.icon(
                            onPressed: _working ? null : _useLocalFallback,
                            icon: const Icon(Icons.lan_rounded),
                            label: const Text('گۆڕین بۆ Local Gateway'),
                          ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _working ? null : _issueToken,
                          icon: const Icon(Icons.key_rounded),
                          label: const Text('دروستکردنی Local Gateway Token'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_working)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
    );
  }
}

class _CloudCredentialInput {
  const _CloudCredentialInput({
    required this.serverAddress,
    required this.appKey,
    required this.secretKey,
  });

  final String serverAddress;
  final String appKey;
  final String secretKey;
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _CloudStatusCard extends StatelessWidget {
  const _CloudStatusCard({
    required this.cloudMode,
    required this.ready,
    required this.configured,
    required this.cameraName,
    required this.channel,
    required this.lastTest,
    required this.queued,
    required this.processing,
    required this.readyCount,
    required this.failed,
  });

  final bool cloudMode;
  final bool ready;
  final bool configured;
  final String cameraName;
  final int channel;
  final String lastTest;
  final int queued;
  final int processing;
  final int readyCount;
  final int failed;

  @override
  Widget build(BuildContext context) {
    final color = ready
        ? Colors.green
        : (configured ? Colors.orange : Colors.grey);
    final title = ready
        ? 'Hik-Connect Cloud چالاکە ✅'
        : configured
            ? 'Cloud پەیوەستە — کامێرا هەڵبژێرە'
            : 'Hik-Connect Cloud هێشتا پەیوەست نییە';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.cloud_done_rounded : Icons.cloud_outlined,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            cloudMode && cameraName.isNotEmpty
                ? '$cameraName • Channel $channel'
                : 'هیچ ئامێری زیادە لە مارکێت پێویست نییە',
          ),
          if (lastTest != '—') Text('کۆتا تاقیکردنەوە: $lastTest'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip('Queue', queued),
              _Chip('Processing', processing),
              _Chip('Ready', readyCount),
              _Chip('Failed', failed),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '$label: $value',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
}