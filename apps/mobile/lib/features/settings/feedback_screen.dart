import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/l10n.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'settings_screen.dart';

/// FEEDBACK01. Text-only feedback (screenshots need upload + scanning, not in this build).
/// Diagnostics default OFF and are previewed exactly as sent. Retries reuse the same
/// Idempotency-Key for the same content so no duplicate ticket is created.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const _draftKey = 'skyweather.feedback.draft';
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _email = TextEditingController();
  String _type = 'bug';
  bool _diagnostics = false;
  PackageInfo? _info;

  String? _idemKey;
  String? _idemSignature;
  bool _sending = false;
  Object? _error;
  String? _ticketId;
  Timer? _saveTimer;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((v) {
      if (mounted) setState(() => _info = v);
    }).catchError((_) {});
    _restore();
    for (final ctl in [_subject, _message, _email]) {
      ctl.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_ticketId == null && _restored) _writeDraft();
    _subject.dispose();
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  // ---- draft persistence ----
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw != null && mounted) {
        final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
        setState(() {
          _type = ['bug', 'suggestion', 'other'].contains(j['type']) ? j['type'] as String : 'bug';
          _subject.text = s(j['subject']) ?? '';
          _message.text = s(j['message']) ?? '';
          _email.text = s(j['email']) ?? '';
          _diagnostics = j['consentDiagnostics'] == true;
          _idemKey = s(j['idempotencyKey']);
          _idemSignature = s(j['idempotencySignature']);
        });
      }
    } catch (_) {}
    _restored = true;
  }

  void _scheduleSave() {
    if (!_restored) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _writeDraft);
  }

  Future<void> _writeDraft() async {
    // Capture synchronously: this also runs from dispose().
    final empty = _subject.text.trim().isEmpty && _message.text.trim().isEmpty && _email.text.trim().isEmpty;
    final raw = jsonEncode({
      'type': _type,
      'subject': _subject.text,
      'message': _message.text,
      'email': _email.text,
      'consentDiagnostics': _diagnostics,
      'idempotencyKey': _idemKey,
      'idempotencySignature': _idemSignature,
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (empty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, raw);
      }
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  // ---- payload ----
  static String _newKey() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  /// Exactly what is sent when "Include diagnostics" is on. No location, no tokens.
  Map<String, String> _diagnosticsPayload(AppSettings st) => {
        'appVersion': _info?.version ?? 'unknown',
        'buildNumber': _info?.buildNumber ?? 'unknown',
        'platform': _platform,
        'locale': st.effectiveLanguage,
      };

  String get _signature => jsonEncode([_type, _subject.text.trim(), _message.text.trim(), _email.text.trim()]);

  Future<void> _submit() async {
    if (_sending) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final st = SettingsScope.read(context);
    // Same content → same key (safe retry). Edited content is a new draft → new key.
    if (_idemKey == null || _idemSignature != _signature) {
      _idemKey = _newKey();
      _idemSignature = _signature;
      await _writeDraft();
    }
    final body = <String, dynamic>{
      'type': _type,
      'subject': _subject.text.trim(),
      'message': _message.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
      'consentDiagnostics': _diagnostics,
      'diagnostics': _diagnostics ? _diagnosticsPayload(st) : null,
      'locale': st.effectiveLanguage,
    };
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.sendFeedback(body, _idemKey!);
      if (!mounted) return;
      _saveTimer?.cancel();
      await _clearDraft();
      if (!mounted) return;
      setState(() {
        _ticketId = s(res['ticketId']) ?? '-';
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'IDEMPOTENCY_CONFLICT') {
        _idemKey = null; // content differs from the first attempt; next tap uses a fresh key
      }
      setState(() {
        _error = e;
        _sending = false;
      });
      _writeDraft();
    }
  }

  void _previewDiagnostics() {
    final st = SettingsScope.read(context);
    final c = SkyColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'Diagnostics preview', 'Xem trước thông tin chẩn đoán')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'Only these fields are sent when the switch is on:', 'Chỉ các trường này được gửi khi bật:'),
                style: TextStyle(color: c.textSecondary)),
            const SizedBox(height: 10),
            for (final e in _diagnosticsPayload(st).entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${e.key}: ${e.value}', style: TextStyle(fontFamily: 'monospace', color: c.textPrimary)),
              ),
            const SizedBox(height: 10),
            Text(tr(context, 'No location, GPS, saved places, keys or tokens are included.', 'Không gồm vị trí, GPS, địa điểm đã lưu, khóa hay token.'),
                style: TextStyle(color: c.textSecondary, fontSize: 13)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'Close', 'Đóng')))],
      ),
    );
  }

  InputDecoration _deco(BuildContext context, String label, {String? hint, String? helper}) {
    final c = SkyColors.of(context);
    OutlineInputBorder b(Color col) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: col));
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      filled: true,
      fillColor: c.card,
      labelStyle: TextStyle(color: c.textSecondary),
      hintStyle: TextStyle(color: c.textMuted),
      helperStyle: TextStyle(color: c.textMuted),
      enabledBorder: b(c.cardBorder),
      focusedBorder: b(c.accent),
      errorBorder: b(Colors.redAccent),
      focusedErrorBorder: b(Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SkyColors.of(context);
    final title = tr(context, 'Send feedback', 'Gửi góp ý');

    if (_ticketId != null) {
      return DetailScaffold(
        title: title,
        centerTitle: false,
        body: UnsupportedView(
          icon: Icons.mark_email_read_outlined,
          title: tr(context, 'Thanks — feedback received', 'Cảm ơn bạn — đã nhận góp ý'),
          message: '${tr(context, 'Ticket', 'Mã phiếu')}: $_ticketId\n'
              '${_email.text.trim().isEmpty ? tr(context, 'No email was given, so we cannot reply directly.', 'Bạn không để lại email nên chúng tôi không thể phản hồi trực tiếp.') : tr(context, 'We will only use your email to reply to this request.', 'Email chỉ được dùng để phản hồi yêu cầu này.')}',
          action: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr(context, 'Done', 'Xong'))),
        ),
      );
    }

    return DetailScaffold(
      title: title,
      centerTitle: false,
      body: Form(
        key: _formKey,
        child: BodyWithAction(
          action: PrimaryButton(
            label: _error != null ? tr(context, 'Retry sending', 'Gửi lại') : tr(context, 'Submit', 'Gửi'),
            icon: Icons.send_rounded,
            busy: _sending,
            onPressed: _submit,
          ),
          children: [
            PillTabs<String>(
              items: [
                ('bug', tr(context, 'Bug report', 'Báo lỗi'), null),
                ('suggestion', tr(context, 'Suggestion', 'Đề xuất'), null),
                ('other', tr(context, 'Other', 'Khác'), null),
              ],
              selected: _type,
              onChanged: (v) {
                setState(() => _type = v);
                _scheduleSave();
              },
            ),
            TextFormField(
              controller: _subject,
              enabled: !_sending,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: c.textPrimary),
              decoration: _deco(context, tr(context, 'Subject', 'Tiêu đề')),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                final n = (v ?? '').trim().length;
                if (n < 5 || n > 120) return tr(context, 'Use 5–120 characters.', 'Dùng 5–120 ký tự.');
                return null;
              },
            ),
            TextFormField(
              controller: _message,
              enabled: !_sending,
              minLines: 5,
              maxLines: 10,
              maxLength: 5000,
              style: TextStyle(color: c.textPrimary),
              decoration: _deco(context, tr(context, 'Message', 'Nội dung'),
                  hint: tr(context, 'What happened, or what would you like to see?', 'Điều gì đã xảy ra, hoặc bạn mong muốn gì?')),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                final n = (v ?? '').trim().length;
                if (n < 10 || n > 5000) return tr(context, 'Use 10–5000 characters.', 'Dùng 10–5000 ký tự.');
                return null;
              },
            ),
            TextFormField(
              controller: _email,
              enabled: !_sending,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: TextStyle(color: c.textPrimary),
              decoration: _deco(context, tr(context, 'Email (optional)', 'Email (không bắt buộc)'),
                  helper: tr(context, 'Only used to reply to this request. No marketing.', 'Chỉ dùng để phản hồi yêu cầu này. Không dùng cho tiếp thị.')),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                if (t.length > 254 || !_emailRe.hasMatch(t)) return tr(context, 'Enter a valid email or leave it empty.', 'Nhập email hợp lệ hoặc để trống.');
                return null;
              },
            ),
            SettingsGroup(
              children: [
                SettingsSwitchRow(
                  icon: Icons.bug_report_outlined,
                  title: tr(context, 'Include diagnostics', 'Kèm thông tin chẩn đoán'),
                  subtitle: tr(context, 'App version, build, platform and language. Off by default.', 'Phiên bản, bản build, nền tảng và ngôn ngữ. Mặc định tắt.'),
                  value: _diagnostics,
                  onChanged: _sending
                      ? null
                      : (v) {
                          setState(() => _diagnostics = v);
                          _scheduleSave();
                        },
                ),
                SettingsRow(
                  icon: Icons.visibility_outlined,
                  title: tr(context, 'Preview', 'Xem trước'),
                  subtitle: tr(context, 'See exactly what would be sent', 'Xem chính xác những gì sẽ được gửi'),
                  onTap: _previewDiagnostics,
                ),
                SettingsRow(
                  icon: Icons.image_not_supported_outlined,
                  title: tr(context, 'Screenshots', 'Ảnh chụp màn hình'),
                  subtitle: tr(context, 'Not supported in this build yet.', 'Bản build này chưa hỗ trợ.'),
                  enabled: false,
                ),
              ],
            ),
            if (_error != null)
              GlassCard(
                borderColor: Colors.redAccent.withValues(alpha: .6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${tr(context, 'Not sent.', 'Chưa gửi được.')} ${errorText(context, _error!)} '
                        '${tr(context, 'Your text is kept — you can retry.', 'Nội dung vẫn được giữ — bạn có thể gửi lại.')}',
                        style: TextStyle(color: c.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
