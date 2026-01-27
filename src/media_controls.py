from pynput import keyboard

class MediaControls:
    def __init__(self, on_play_pause, on_next, on_prev):
        self.on_play_pause = on_play_pause
        self.on_next = on_next
        self.on_prev = on_prev
        self.listener = None

    def start(self):
        self.listener = keyboard.GlobalHotKeys({
            '<media_play_pause>': self.on_play_pause,
            '<media_next>': self.on_next,
            '<media_previous>': self.on_prev
        })
        self.listener.start()

    def stop(self):
        if self.listener:
            self.listener.stop()
