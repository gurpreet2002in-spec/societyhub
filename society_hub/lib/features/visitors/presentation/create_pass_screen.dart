import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/visitor_provider.dart';

class CreatePassScreen extends ConsumerStatefulWidget {
  const CreatePassScreen({super.key});

  @override
  ConsumerState<CreatePassScreen> createState() => _CreatePassScreenState();
}

class _CreatePassScreenState extends ConsumerState<CreatePassScreen> {
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  String _purpose = 'Guest';
  final DateTime _expectedEntry = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Visitor'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Visitor Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _purpose,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                labelText: 'Purpose',
              ),
              items: const [
                DropdownMenuItem(value: 'Guest', child: Text('Guest')),
                DropdownMenuItem(value: 'Delivery', child: Text('Delivery')),
                DropdownMenuItem(value: 'Cab', child: Text('Cab')),
                DropdownMenuItem(value: 'Service', child: Text('Service')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _purpose = val);
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                if (_nameController.text.isEmpty || _mobileController.text.isEmpty) return;
                try {
                  await ref.read(visitorsProvider.notifier).preapproveVisitor(
                    _nameController.text,
                    _mobileController.text,
                    _purpose,
                    _expectedEntry,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pass created successfully!')));
                    context.pop();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
              ),
              child: const Text('Generate Pass', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
