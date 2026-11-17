import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class ComingSoonScreen extends StatefulWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.body,
    this.collectEmail = false,
  });

  final String title;
  final String body;
  final bool collectEmail;

  @override
  State<ComingSoonScreen> createState() => _ComingSoonScreenState();
}

class _ComingSoonScreenState extends State<ComingSoonScreen> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coming soon')),
      body: SafeArea(
        child: CofinexFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              const CofinexMark(size: 72),
              const SizedBox(height: 24),
              Text(
                widget.title,
                key: const Key('coming-soon-title'),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                widget.body,
                style: const TextStyle(
                  color: CofinexColors.muted,
                  height: 1.45,
                  fontSize: 16,
                ),
              ),
              if (widget.collectEmail) ...[
                const SizedBox(height: 24),
                TextField(
                  key: const Key('email-field'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'Kept on this screen only. Nothing is sent.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
