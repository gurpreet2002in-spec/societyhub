import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/amenity_provider.dart';

class AmenitiesScreen extends ConsumerStatefulWidget {
  const AmenitiesScreen({super.key});

  @override
  ConsumerState<AmenitiesScreen> createState() => _AmenitiesScreenState();
}

class _AmenitiesScreenState extends ConsumerState<AmenitiesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final asyncAmenities = ref.watch(amenitiesProvider);
    final asyncBookings = ref.watch(myBookingsProvider);

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Amenities', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Book'),
            Tab(text: 'My Bookings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAmenitiesGrid(context, asyncAmenities),
          _buildMyBookings(context, asyncBookings),
        ],
      ),
    );
  }

  Widget _buildAmenitiesGrid(BuildContext context, AsyncValue<List<dynamic>> asyncAmenities) {
    return asyncAmenities.when(
      data: (amenities) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.88,
        ),
        itemCount: amenities.length,
        itemBuilder: (ctx, i) => _buildAmenityCard(ctx, amenities[i]),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildAmenityCard(BuildContext context, Map<String, dynamic> amenity) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showBookingSheet(context, amenity),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.primaryContainer.withValues(alpha: 0.5), colors.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.primary.withValues(alpha: 0.1)),
          boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(amenity['imageEmoji'] ?? '\u{1F3E2}', style: const TextStyle(fontSize: 40)),
              const Spacer(),
              Text(amenity['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text(amenity['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.people_outline, size: 13, color: colors.primary),
                const SizedBox(width: 3),
                Text('${amenity['capacity']} max', style: TextStyle(fontSize: 11, color: colors.primary, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: amenity['pricePerHour'] == 0 ? Colors.green.withValues(alpha: 0.1) : colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    amenity['pricePerHour'] == 0 ? 'FREE' : '\u20B9${amenity['pricePerHour']}/hr',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                        color: amenity['pricePerHour'] == 0 ? Colors.green : colors.primary),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyBookings(BuildContext context, AsyncValue<List<dynamic>> asyncBookings) {
    return asyncBookings.when(
      data: (bookings) {
        if (bookings.isEmpty) {
          return const Center(child: Text('No bookings yet.', style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (ctx, i) => _buildBookingCard(ctx, bookings[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildBookingCard(BuildContext context, Map<String, dynamic> b) {
    final isConfirmed = b['status'] == 'confirmed';
    final amenityName = b['Amenity']?['name'] ?? 'Amenity';
    final emoji = b['Amenity']?['imageEmoji'] ?? '\u{1F3E2}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(amenityName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${b['bookingDate']}  ${b['startTime']} \u2013 ${b['endTime']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if ((b['totalAmount'] ?? 0) > 0)
                  Text('\u20B9${b['totalAmount']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (isConfirmed)
            TextButton(
              onPressed: () async {
                await ref.read(myBookingsProvider.notifier).cancel(b['id']);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Booking cancelled')));
                }
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(b['status']?.toString().toUpperCase() ?? '',
                  style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  void _showBookingSheet(BuildContext context, Map<String, dynamic> amenity) {
    DateTime selectedDate = DateTime.now();
    String startTime = '09:00';
    String endTime = '10:00';

    final List<String> timeSlots = List.generate(
      17, (i) => '${(6 + i).toString().padLeft(2, '0')}:00',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 24, right: 24, top: 24,
          ),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text(amenity['imageEmoji'] ?? '\u{1F3E2}', style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(amenity['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('Open: ${amenity['openTime']} \u2013 ${amenity['closeTime']}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ]),
              const SizedBox(height: 20),
              // Date picker
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (d != null) setState(() => selectedDate = d);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(14),
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 18),
                    const SizedBox(width: 10),
                    Text(DateFormat('EEE, MMM d yyyy').format(selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    const Icon(Icons.edit, size: 16, color: Colors.grey),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: startTime,
                    decoration: InputDecoration(
                      labelText: 'Start Time',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    items: timeSlots.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => startTime = v ?? startTime),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: endTime,
                    decoration: InputDecoration(
                      labelText: 'End Time',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    items: timeSlots.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => endTime = v ?? endTime),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
                    await ref.read(amenitiesProvider.notifier).book(
                        amenity['id'], dateStr, startTime, endTime);
                    ref.invalidate(myBookingsProvider);
                    if (context.mounted) {
                      Navigator.pop(context);
                      _tabController.animateTo(1);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('\u2705 Booking confirmed!'), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e'), backgroundColor: Colors.red));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  amenity['pricePerHour'] == 0 ? 'Book Now (Free)' : 'Confirm Booking',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
