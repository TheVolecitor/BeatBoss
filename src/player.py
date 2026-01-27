import flet as ft
import flet_audio
import threading
import time

class AudioPlayer:
    def __init__(self, page: ft.Page):
        self.page = page
        self.current_track = None
        self.is_playing = False
        self._volume = 0.8  # 0.0 to 1.0 for Flet
        self.on_track_end = None
        self.on_error = None
        self.active = True
        
        # State tracking
        self.duration = 0
        self.current_position = 0
        
        # Initialize Audio Control
        self.audio = flet_audio.Audio(
            autoplay=False,
            volume=self._volume,
            on_loaded=self._on_loaded,
            on_duration_change=self._on_duration_changed,
            on_position_change=self._on_position_changed,
            on_state_change=self._on_state_changed,
            on_seek_complete=self._on_seek_complete,
        )
        
        
        # Add to page overlay - NOT NEEDED for flet_audio apparently, causes Unknown Control error
        # self.page.overlay.append(self.audio)
        # self.page.update()
        
    def _on_loaded(self, e):
        print(f"[FletAudio] Media loaded")
        self.is_playing = True
        self.page.run_task(self.audio.play)
        self.page.update()

    def _on_duration_changed(self, e):
        # e.duration is a Duration object
        try:
            if hasattr(e.duration, 'total_seconds'):
                self.duration = int(e.duration.total_seconds() * 1000)
            else:
                # Manual summation
                d = e.duration
                ms = 0
                if hasattr(d, 'days'): ms += d.days * 86400000
                if hasattr(d, 'hours'): ms += d.hours * 3600000
                if hasattr(d, 'minutes'): ms += d.minutes * 60000
                if hasattr(d, 'seconds'): ms += d.seconds * 1000
                if hasattr(d, 'milliseconds'): ms += d.milliseconds
                self.duration = int(ms)
        except Exception as ex:
            print(f"Error parsing duration: {ex}, type: {type(e.duration)}")
            self.duration = 0

    def _on_position_changed(self, e):
        # e.position is a Duration object
        try:
            if hasattr(e.position, 'total_seconds'):
                ms = int(e.position.total_seconds() * 1000)
            else:
                p = e.position
                val = 0
                if hasattr(p, 'days'): val += p.days * 86400000
                if hasattr(p, 'hours'): val += p.hours * 3600000
                if hasattr(p, 'minutes'): val += p.minutes * 60000
                if hasattr(p, 'seconds'): val += p.seconds * 1000
                if hasattr(p, 'milliseconds'): val += p.milliseconds
                ms = int(val)
            
            # STABILITY FIX: Ignore 0ms flinches
            recently_seeked = (time.time() - getattr(self, '_last_seek_time', 0)) < 2.0
            if ms == 0 and self.current_position > 2000 and not recently_seeked:
                return
                
            self.current_position = ms
        except Exception as ex:
            pass

    def _on_state_changed(self, e):
        # e is AudioStateChangeEvent, has .state property
        # state: "playing", "paused", "completed" (or AudioState enum)
        state = str(e.state).lower()
        if "completed" in state:
            self.is_playing = False
            if self.on_track_end:
                 # Run callback in thread to avoid blocking Flet UI
                threading.Thread(target=self.on_track_end, daemon=True).start()
        elif "playing" in state:
            self.is_playing = True
        elif "paused" in state:
            self.is_playing = False

    def _on_seek_complete(self, e):
        pass

    def play_url(self, url, track_info=None):
        try:
            self.current_track = track_info
            print(f"[FletAudio] Request to play: {url}")
            
            async def _play_async():
                try:
                    # 1. Define Monitor Loop first so it's available
                    async def _monitor_loop():
                        while self.is_playing:
                            try:
                                # Poll duration
                                dur = await self.audio.get_duration()
                                
                                if dur is not None:
                                    if hasattr(dur, 'total_seconds'): 
                                        self.duration = int(dur.total_seconds() * 1000)
                                    else:
                                        # Manually sum components if it's flet Duration object
                                        try:
                                            ms = 0
                                            if hasattr(dur, 'days'): ms += dur.days * 86400000
                                            if hasattr(dur, 'hours'): ms += dur.hours * 3600000
                                            if hasattr(dur, 'minutes'): ms += dur.minutes * 60000
                                            if hasattr(dur, 'seconds'): ms += dur.seconds * 1000
                                            if hasattr(dur, 'milliseconds'): ms += dur.milliseconds
                                            if hasattr(dur, 'microseconds'): ms += dur.microseconds / 1000
                                            self.duration = int(ms)
                                        except:
                                            # Fallback
                                            if hasattr(dur, 'milliseconds'): self.duration = int(dur.milliseconds)
                                            else: self.duration = int(dur)
                                        
                                # Poll position
                                pos = await self.audio.get_current_position()
                                if pos is not None:
                                    # Manually sum components for Flet Duration
                                    try:
                                        ms = 0
                                        if hasattr(pos, 'days'): ms += pos.days * 86400000
                                        if hasattr(pos, 'hours'): ms += pos.hours * 3600000
                                        if hasattr(pos, 'minutes'): ms += pos.minutes * 60000
                                        if hasattr(pos, 'seconds'): ms += pos.seconds * 1000
                                        if hasattr(pos, 'milliseconds'): ms += pos.milliseconds
                                        new_pos = int(ms)
                                        
                                        # STABILITY FIX: Ignore 0ms updates if we've already progressed 
                                        # (unless we're at the very start or just finished a seek)
                                        recently_seeked = (time.time() - getattr(self, '_last_seek_time', 0)) < 2.0
                                        if new_pos == 0 and self.current_position > 2000 and not recently_seeked:
                                            # print("[Monitor] Ignoring suspicious 0ms position update")
                                            pass
                                        else:
                                            self.current_position = new_pos
                                            # Sync synthetic timer to real position
                                            self._start_time = time.time() - (self.current_position / 1000.0)
                                            # Update last pos update heartbeat
                                            self._last_pos_update = time.time()
                                    except:
                                        pass
                                else:
                                    # FALLBACK: Synthetic position update
                                    elapsed = (time.time() - self._start_time) * 1000
                                    if elapsed > 0:
                                        self.current_position = int(elapsed)
                                        # Clamp to duration if known
                                        if self.duration > 0 and self.current_position > self.duration:
                                            self.current_position = self.duration
                            except Exception as ex:
                                pass
                            
                            import asyncio
                            await asyncio.sleep(0.5)

                    # 2. Release previous audio if exists
                    if hasattr(self, 'audio') and self.audio:
                        try:
                            print(f"[FletAudio] Releasing previous audio...")
                            await self.audio.release()
                        except: pass
                    
                    print(f"[FletAudio] Creating NEW Audio instance...")
                    self.audio = flet_audio.Audio(
                        src=url,
                        autoplay=False,
                        volume=self._volume,
                        on_loaded=self._on_loaded,
                        on_duration_change=self._on_duration_changed,
                        on_position_change=self._on_position_changed,
                        on_state_change=self._on_state_changed,
                        on_seek_complete=self._on_seek_complete,
                    )
                    
                    
                    # 3. Parse Metadata Duration (if available)
                    if track_info and "duration" in track_info:
                        try:
                            d = track_info["duration"]
                            if isinstance(d, (int, float)):
                                # Heuristic: if duration is huge (>10000), it's likely ms already.
                                if int(d) > 10000:
                                    self.duration = int(d)
                                else:
                                    self.duration = int(d * 1000)
                            elif isinstance(d, str) and ":" in d:
                                parts = d.split(":")
                                if len(parts) == 2:
                                    self.duration = (int(parts[0]) * 60 + int(parts[1])) * 1000
                                elif len(parts) == 3:
                                    self.duration = (int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])) * 1000
                        except Exception as e:
                             print(f"[FletAudio] Metadata parse error: {e}")

                    # 4. Initialize Tracking and Start Monitoring
                    self._start_time = time.time()
                    self._last_pos_update = 0
                    self.is_playing = True
                    self.page.run_task(_monitor_loop)
                    
                    # 5. Start Playback
                    print(f"[FletAudio] Calling play()...")
                    await self.audio.play()
                    print(f"[FletAudio] Playback started successfully: {url}")

                except Exception as e:
                    print(f"[FletAudio] Async Play Error: {e}")
                    import traceback
                    traceback.print_exc()

            self.page.run_task(_play_async)
            
        except Exception as e:
            print(f"[FletAudio] Play Error: {e}")
            if self.on_error:
                threading.Thread(target=self.on_error, daemon=True).start()

    def toggle_play_pause(self):
        if self.is_playing:
            self.pause()
        else:
            self.resume()
        return self.is_playing

    def pause(self):
        async def _pause_async():
            await self.audio.pause()
            
        self.page.run_task(_pause_async)
        self.is_playing = False

    def resume(self):
        async def _resume_async():
            await self.audio.resume()
            
        self.page.run_task(_resume_async)
        self.is_playing = True

    def stop(self):
        async def _stop_async():
            await self.audio.pause()
            
        self.page.run_task(_stop_async)
        self.is_playing = False

    def set_volume(self, volume):
        self._volume = float(volume) / 100.0
        self.audio.volume = self._volume
        self.audio.update()

    def get_time(self):
        return self.current_position

    def get_length(self):
        return self.duration

    def set_position(self, position):
        """Set position by percentage (0.0 to 1.0)"""
        if self.duration > 0:
            ms = int(position * self.duration)
            self.seek(ms)

    def seek(self, ms):
        """Seek to position in ms"""
        async def _seek_async():
            # Using ft.Duration as per example/docs to be safe
            await self.audio.seek(ft.Duration(milliseconds=int(ms)))
            # Update synthetic tracking base
            self._start_time = time.time() - (ms / 1000.0)
            self.current_position = int(ms) # Updating immediate pos
            
        self.page.run_task(_seek_async)

    def release(self):
        async def _release_async():
            try:
                await self.audio.release()
                # if self.audio in self.page.overlay:
                #     self.page.overlay.remove(self.audio)
                #     self.page.update()
            except:
                pass
                
        self.page.run_task(_release_async)
