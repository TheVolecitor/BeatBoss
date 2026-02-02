import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/dab_api_service.dart';
import '../../core/services/settings_service.dart';

class BatchDownloadDialog extends StatefulWidget {
  final List<Track> tracks;

  const BatchDownloadDialog({super.key, required this.tracks});

  @override
  State<BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<BatchDownloadDialog> {
  bool _calculating = true;
  List<Track> _toDownload = [];
  int _alreadyDownloadedCount = 0;

  // Progress
  bool _started = false;
  int _completed = 0;
  int _failed = 0;
  int _total = 0;
  String? _statusMessage;

  // Concurrency
  final int _batchSize = 5;

  @override
  void initState() {
    super.initState();
    _calculateDownloads();
  }

  Future<void> _calculateDownloads() async {
    final settings = context.read<SettingsService>();
    final List<Track> pending = [];
    int exists = 0;

    for (final track in widget.tracks) {
      if (settings.isDownloaded(track.id)) {
        exists++;
      } else {
        pending.add(track);
      }
    }

    if (mounted) {
      setState(() {
        _toDownload = pending;
        _alreadyDownloadedCount = exists;
        _calculating = false;
        _total = pending.length;
      });
    }
  }

  void _startDownload() async {
    setState(() {
      _started = true;
      _statusMessage = 'Starting batch download...';
    });

    final dlService = context.read<DownloadManagerService>();
    final apiService = context.read<DabApiService>();

    // Process in batches
    for (int i = 0; i < _toDownload.length; i += _batchSize) {
      if (!mounted)
        break; // Check if user forced closed (though we try to prevent it)

      final end = (i + _batchSize < _toDownload.length)
          ? i + _batchSize
          : _toDownload.length;
      final batch = _toDownload.sublist(i, end);

      setState(() {
        _statusMessage = 'Downloading ${i + 1} - $end of $_total...';
      });

      if (_stopRequested) break; // Exit loop if stopped

      // Execute batch concurrently
      await Future.wait(batch.map((track) async {
        try {
          // We need to fetch the stream URL fresh usually,
          // but if we are in Favorites, we might not have it or it might be expired.
          // DownloadManager requires streamUrl.
          // We must fetch stream URL for each track if not present/valid.
          // Assuming we need to fetch it:

          String? streamUrl;
          try {
            streamUrl = await apiService.getStreamUrl(track.id);
          } catch (e) {
            print('Error fetching stream for ${track.title}: $e');
          }

          if (streamUrl != null) {
            final success = await dlService.downloadTrack(
              track: track,
              streamUrl: streamUrl,
              onProgress:
                  (p) {}, // We don't track individual progress in this aggregate view strictly
            );
            if (success)
              _completed++;
            else
              _failed++;
          } else {
            _failed++;
          }
        } catch (e) {
          _failed++;
        }
        if (mounted) setState(() {});
      }));
    }

    if (mounted) {
      setState(() {
        _statusMessage = 'Completed! Success: $_completed, Failed: $_failed';
      });
      // Delay to let user see result
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
  }

  void _stopDownload() {
    setState(() {
      _started = false; // Allow cancelling/closing
      // We don't strictly set _stopped flag since checking mounted serves similar purpose,
      // but breaking the loop requires a flag or check.
      // Let's rely on modifying the _toDownload list or index?
      // Better: Using a flag is cleaner.
    });
  }

  // Flag to control the loop
  bool _stopRequested = false;

  @override
  Widget build(BuildContext context) {
    // Prevent back button unless finished or stopped
    // If _stopRequested is true, we allow popping.
    // If !_started is true (initial state), we allow popping.
    // If completed+failed == total, we allow popping.
    bool canPop =
        !_started || _stopRequested || (_completed + _failed == _total);

    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please stop downloads before closing.')),
        );
      },
      child: AlertDialog(
        title: const Text('Download All'),
        content: _calculating
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : !_started && !_stopRequested
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Found ${widget.tracks.length} songs.'),
                      if (_alreadyDownloadedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                              '$_alreadyDownloadedCount songs are already downloaded and will be skipped.',
                              style: const TextStyle(color: Colors.orange)),
                        ),
                      const SizedBox(height: 15),
                      Text(
                        _toDownload.isNotEmpty
                            ? 'Ready to download ${_toDownload.length} songs.'
                            : 'All songs are already downloaded!',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_toDownload.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Please stay on this screen while downloading.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: _total > 0 ? (_completed + _failed) / _total : 0,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation(Colors.green),
                      ),
                      const SizedBox(height: 15),
                      Text(_stopRequested
                          ? 'Download Stopped'
                          : '$_statusMessage'),
                      const SizedBox(height: 5),
                      Text('$_completed / $_total completed'),
                      if (_failed > 0)
                        Text('$_failed failed',
                            style: const TextStyle(color: Colors.red)),
                    ],
                  ),
        actions: [
          if (!_started && !_stopRequested) ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (_toDownload.isNotEmpty)
              ElevatedButton(
                onPressed: _startDownload,
                child: Text('Download ${_toDownload.length} Songs'),
              ),
          ] else if (_stopRequested || (_completed + _failed == _total)) ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ] else ...[
            // Running state
            TextButton(
              onPressed: () {
                setState(() => _stopRequested = true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Stop Now'),
            ),
          ],
        ],
      ),
    );
  }
}
