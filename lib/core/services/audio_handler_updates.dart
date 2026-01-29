// ... inside AppAudioHandler

Future<void> setVolume(double volume) async {
  await _player.setVolume(volume);
}

@override
Future<void> skipToQueueItem(int index) async {
  await _playQueueItem(index);
}

Future<void> removeFromQueue(int index) async {
  if (index >= 0 && index < _internalQueue.length) {
    _internalQueue.removeAt(index);
    // Update Queue Stream
    queue.add(_internalQueue.map(_toMediaItem).toList());

    // If we removed the current track, what happens?
    if (index == _currentIndex) {
      // Play next or stop?
      if (_internalQueue.isEmpty) {
        stop();
      } else {
        if (_currentIndex >= _internalQueue.length) _currentIndex = 0;
        await _playQueueItem(_currentIndex);
      }
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
  }
}
