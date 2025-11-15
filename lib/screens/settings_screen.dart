import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  final TextEditingController _phoneController = TextEditingController();
  String? _savedPhoneNumber;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPhone();
  }

  Future<void> _loadSavedPhone() async {
    setState(() {
      _isLoading = true;
    });

    final savedPhone = await _settingsService.getTrustedPersonPhone();

    setState(() {
      _savedPhoneNumber = savedPhone;
      _phoneController.text = savedPhone ?? '';
      _isLoading = false;
    });
  }

  Future<void> _savePhone() async {
    final phoneNumber = _phoneController.text.trim();

    if (phoneNumber.isEmpty) {
      _showSnackBar('Please enter a phone number', isError: true);
      return;
    }

    if (!_settingsService.isValidPhoneNumber(phoneNumber)) {
      _showSnackBar(
        'Please enter a valid phone number (at least 10 digits)',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final formattedPhone = _settingsService.formatPhoneNumber(phoneNumber);
    final success = await _settingsService.saveTrustedPersonPhone(
      formattedPhone,
    );

    setState(() {
      _isSaving = false;
    });

    if (success) {
      setState(() {
        _savedPhoneNumber = formattedPhone;
      });
      _showSnackBar('Trusted person phone number saved');
      // Dismiss keyboard
      FocusScope.of(context).unfocus();
    } else {
      _showSnackBar('Failed to save phone number', isError: true);
    }
  }

  Future<void> _clearPhone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Trusted Person?'),
        content: const Text(
          'Are you sure you want to remove the trusted person phone number? '
          'The AI agent will not be able to add them to calls if fraud is detected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _settingsService.clearTrustedPersonPhone();

      if (success) {
        setState(() {
          _savedPhoneNumber = null;
          _phoneController.clear();
        });
        _showSnackBar('Trusted person phone number removed');
      } else {
        _showSnackBar('Failed to remove phone number', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.grey[850],
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trusted Person Section
                  Card(
                    color: Colors.grey[800],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.contact_phone,
                                color: Colors.blue[300],
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Trusted Person',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Set a trusted person\'s phone number (like a family member or close friend). '
                            'When the AI detects a potential scam during a call, it can automatically add '
                            'this trusted person to the call to help protect you.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Current saved number display
                          if (_savedPhoneNumber != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green[900]?.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green[700]!,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green[400],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Saved Number:',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          _savedPhoneNumber!,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Phone number input
                          TextField(
                            controller: _phoneController,
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              hintText: '+1234567890 or 1234567890',
                              prefixIcon: const Icon(Icons.phone),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[700],
                              labelStyle: const TextStyle(color: Colors.grey),
                              hintStyle: TextStyle(color: Colors.grey[500]),
                            ),
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d+\s\-\(\)]'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isSaving ? null : _savePhone,
                                  icon: _isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : const Icon(Icons.save),
                                  label: Text(_isSaving ? 'Saving...' : 'Save'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[700],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              if (_savedPhoneNumber != null) ...[
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _clearPhone,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remove'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[700],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
