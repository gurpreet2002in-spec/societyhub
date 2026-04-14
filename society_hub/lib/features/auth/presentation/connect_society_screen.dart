import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../services/api_service.dart';
import '../../../core/theme/app_theme.dart';

class ConnectSocietyScreen extends ConsumerStatefulWidget {
  const ConnectSocietyScreen({super.key});

  @override
  ConsumerState<ConnectSocietyScreen> createState() => _ConnectSocietyScreenState();
}

class _ConnectSocietyScreenState extends ConsumerState<ConnectSocietyScreen> {
  final _urlController = TextEditingController();
  final _societyIdController = TextEditingController();
  bool _isLoading = false;
  bool _showScanner = false;
  MobileScannerController? _scannerController;

  @override
  void dispose() {
    _urlController.dispose();
    _societyIdController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_urlController.text.isEmpty || _societyIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter server URL and society ID')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final baseUrl = _urlController.text.trim();
      final societyId = _societyIdController.text.trim();

      final apiService = ref.read(apiServiceProvider);
      await apiService.setServerUrl(baseUrl);

      await apiService.testConnection(societyId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected successfully!'), backgroundColor: Colors.green),
      );
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue;
    if (code == null) return;

    try {
      final data = jsonDecode(code);
      if (data['serverUrl'] != null && data['societyId'] != null) {
        _scannerController?.stop();
        setState(() => _showScanner = false);
        _urlController.text = data['serverUrl'];
        _societyIdController.text = data['societyId'];
        _connect();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid QR code format')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _showScanner ? _buildScanner() : _buildForm(),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController ??= MobileScannerController(),
          onDetect: _onDetect,
        ),
        Positioned(
          top: 16,
          left: 16,
          child: IconButton(
            onPressed: () => setState(() => _showScanner = false),
            icon: const Icon(Icons.close, color: Colors.white, size: 32),
          ),
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Text(
            'Point camera at society QR code',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.apartment,
            size: 80,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'SocietyHub',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect to your society',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 48),
          Text(
            'Scan QR Code',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _showScanner = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
                color: AppTheme.primary.withOpacity(0.05),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 48,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to scan QR code',
                    style: GoogleFonts.poppins(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey[300])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR',
                  style: GoogleFonts.poppins(color: Colors.grey[500]),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey[300])),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Enter Details Manually',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://your-society.railway.app',
              prefixIcon: const Icon(Icons.link),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _societyIdController,
            decoration: InputDecoration(
              labelText: 'Society ID',
              hintText: 'Enter society code',
              prefixIcon: const Icon(Icons.business),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Connect',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}