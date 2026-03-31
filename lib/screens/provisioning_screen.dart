import 'package:flutter/material.dart';
import 'package:home_automation_app1/services/wifi_provision_service.dart';

class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

enum _ProvisionStep {
  instructions,
  checkConnection,
  enterCredentials,
  sending,
  success,
  error,
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  _ProvisionStep _step = _ProvisionStep.instructions;
  String _errorMessage = '';
  bool _passwordVisible = false;

  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    setState(() => _step = _ProvisionStep.checkConnection);
    final reachable = await WifiProvisionService.isReachable();
    if (!mounted) return;
    if (reachable) {
      setState(() => _step = _ProvisionStep.enterCredentials);
    } else {
      setState(() {
        _errorMessage =
            'Could not reach the ESP32.\n\nMake sure your phone is connected to the "ESP32-Setup" WiFi hotspot, then try again.';
        _step = _ProvisionStep.error;
      });
    }
  }

  Future<void> _sendCredentials() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = _ProvisionStep.sending);

    final result = await WifiProvisionService.configure(
      ssid: _ssidController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() => _step = _ProvisionStep.success);
    } else {
      setState(() {
        _errorMessage = result.message;
        _step = _ProvisionStep.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up device WiFi')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      _ProvisionStep.instructions => _InstructionsStep(
        onNext: _checkConnection,
      ),
      _ProvisionStep.checkConnection => const _LoadingStep(
        message: 'Checking connection to ESP32...',
      ),
      _ProvisionStep.enterCredentials => _CredentialsStep(
        formKey: _formKey,
        ssidController: _ssidController,
        passwordController: _passwordController,
        passwordVisible: _passwordVisible,
        onTogglePassword: () =>
            setState(() => _passwordVisible = !_passwordVisible),
        onSubmit: _sendCredentials,
      ),
      _ProvisionStep.sending => const _LoadingStep(
        message:
            'Sending credentials to ESP32...\nThis may take up to 30 seconds.',
      ),
      _ProvisionStep.success => _SuccessStep(
        onDone: () => Navigator.pop(context),
      ),
      _ProvisionStep.error => _ErrorStep(
        message: _errorMessage,
        onRetry: () => setState(() => _step = _ProvisionStep.instructions),
      ),
    };
  }
}

// ── Step widgets ──────────────────────────────────────────────────────────────

class _InstructionsStep extends StatelessWidget {
  final VoidCallback onNext;
  const _InstructionsStep({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.wifi_tethering, size: 48),
        const SizedBox(height: 16),
        Text(
          'Connect to the device hotspot',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        _StepItem(number: '1', text: "Open your phone's WiFi settings."),
        _StepItem(
          number: '2',
          text: 'Connect to the network called "ESP32-Setup".',
        ),
        _StepItem(number: '3', text: 'Come back to this app and tap Continue.'),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onNext,
            child: const Text("I'm connected — Continue"),
          ),
        ),
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  final String number;
  final String text;
  const _StepItem({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 14, child: Text(number)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _LoadingStep extends StatelessWidget {
  final String message;
  const _LoadingStep({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _CredentialsStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final bool passwordVisible;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;

  const _CredentialsStep({
    required this.formKey,
    required this.ssidController,
    required this.passwordController,
    required this.passwordVisible,
    required this.onTogglePassword,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter your WiFi details',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'The ESP32 will connect to this network. You can change it later from Settings.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: ssidController,
            decoration: const InputDecoration(
              labelText: 'WiFi network name (SSID)',
              prefixIcon: Icon(Icons.wifi),
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please enter the network name'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: passwordController,
            obscureText: !passwordVisible,
            decoration: InputDecoration(
              labelText: 'WiFi password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  passwordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: onTogglePassword,
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSubmit,
              child: const Text('Save & Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessStep extends StatelessWidget {
  final VoidCallback onDone;
  const _SuccessStep({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            'Device configured!',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'The ESP32 is restarting and connecting to your WiFi.\n\n'
            'Please reconnect your phone to your normal WiFi network — '
            'the app will then connect automatically via MQTT.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}

class _ErrorStep extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorStep({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
