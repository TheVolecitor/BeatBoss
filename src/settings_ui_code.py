# Settings UI and Download Integration Code

# Add this method to DabFletApp class (around line 850)

def _show_settings(self):
    """Display settings panel"""
    self.current_view = "settings"
    self.viewport.controls.clear()
    self.viewport.controls.append(ft.Text("Settings", size=32, weight="bold"))
    self.viewport.controls.append(ft.Container(height=20))
    
    # Theme Setting
    theme_label = ft.Text("Theme", size=18, weight="bold")
    current_theme = self.settings.get_theme()
    
    def _on_theme_change(e):
        new_theme = "light" if e.control.value else "dark"
        self.settings.set_theme(new_theme)
        self.page.theme_mode = ft.ThemeMode.LIGHT if new_theme == "light" else ft.ThemeMode.DARK
        self.page.bgcolor = "#FFFFFF" if new_theme == "light" else "#020202"
        self.page.update()
        self.page.snack_bar = ft.SnackBar(ft.Text(f"Theme changed to {new_theme.title()}"))
        self.page.snack_bar.open = True
        self.page.update()
    
    theme_switch = ft.Switch(
        label="Light Mode",
        value=current_theme == "light",
        on_change=_on_theme_change
    )
    
    theme_row = ft.Row([theme_label, theme_switch], spacing=20)
    
    # Download Location Setting
    download_label = ft.Text("Download Location", size=18, weight="bold")
    current_location = self.settings.get_download_location()
    location_text = ft.Text(current_location, size=14, color=ft.Colors.WHITE_70)
    
    def _browse_location(e):
        # For now, show a text field to enter path
        # In a full implementation, you'd use a folder picker dialog
        pass
    
    browse_btn = ft.IconButton(
        icon=ft.Icons.FOLDER_OPEN,
        tooltip="Browse",
        on_click=_browse_location
    )
    
    location_row = ft.Row([download_label, location_text, browse_btn], spacing=10)
    
    # Storage Info
    downloaded_count = self.settings.get_downloaded_count()
    storage_size = self.settings.get_storage_size()
    storage_mb = storage_size / (1024 * 1024)
    
    storage_info = ft.Text(
        f"Downloaded Tracks: {downloaded_count} ({storage_mb:.2f} MB)",
        size=14,
        color=ft.Colors.WHITE_70
    )
    
    # Clear Cache Button
    def _clear_cache(e):
        self.settings.clear_cache()
        self.page.snack_bar = ft.SnackBar(ft.Text("Cache cleared successfully"))
        self.page.snack_bar.open = True
        self._show_settings()  # Refresh view
    
    clear_btn = ft.ElevatedButton(
        "Clear Downloaded Tracks",
        icon=ft.Icons.DELETE_SWEEP,
        on_click=_clear_cache,
        bgcolor=ft.Colors.RED_700,
        color=ft.Colors.WHITE
    )
    
    # Add all to viewport
    settings_container = ft.Container(
        content=ft.Column([
            theme_row,
            ft.Container(height=20),
            location_row,
            ft.Container(height=20),
            storage_info,
            ft.Container(height=10),
            clear_btn
        ]),
        padding=20,
        bgcolor="#0A0A0A",
        border_radius=15,
        width=600
    )
    
    self.viewport.controls.append(settings_container)
    self.page.update()


# Modify _display_tracks to add download button (around line 500)
# Add this inside the track row creation, after the play button:

def _display_tracks_with_download(self, tracks):
    """Display tracks with download buttons"""
    grid = ft.Column(spacing=15)
    for i, t in enumerate(tracks):
        track_id = t.get("id")
        track_img = ft.Container(width=55, height=55, bgcolor="#1A1A1A", border_radius=8)
        
        # Hi-Res Badge
        is_hires = t.get("audioQuality", {}).get("isHiRes", False)
        hires_badge = ft.Container(
            content=ft.Text("HI-RES", size=9, color=ft.Colors.BLACK, weight="bold"),
            bgcolor=ft.Colors.GREEN,
            padding=ft.Padding(6, 2, 6, 2),
            border_radius=4,
            visible=is_hires
        )
        
        # Download button or checkmark
        is_downloaded = self.download_manager.is_downloaded(track_id)
        
        if is_downloaded:
            download_btn = ft.IconButton(
                ft.Icons.CHECK_CIRCLE,
                icon_color=ft.Colors.GREEN,
                tooltip="Downloaded",
                icon_size=20
            )
        else:
            def _download_track(_, trk=t):
                track_id = trk.get("id")
                # Get stream URL
                stream_url = self.api.get_stream_url(track_id)
                if stream_url:
                    # Start download
                    self.download_manager.download_track(
                        track_id,
                        stream_url,
                        trk.get("title"),
                        trk.get("artist"),
                        completion_callback=lambda tid, success, msg: self._on_download_complete(tid, success, msg)
                    )
                    self.page.snack_bar = ft.SnackBar(ft.Text(f"Downloading: {trk.get('title')}"))
                    self.page.snack_bar.open = True
                    self.page.update()
            
            download_btn = ft.IconButton(
                ft.Icons.DOWNLOAD,
                icon_color=ft.Colors.WHITE_30,
                tooltip="Download",
                icon_size=20,
                on_click=_download_track
            )
        
        # Collection menu
        items=[
            ft.PopupMenuItem(content=ft.Text("Add to Library"), on_click=lambda _, trk=t: self._add_to_lib_picker(trk)),
            ft.PopupMenuItem(content=ft.Text("Add to Queue"), on_click=lambda _, trk=t: self._add_to_queue(trk)),
            ft.PopupMenuItem(content=ft.Text("Like"), on_click=lambda _, trk=t: self._like_track(trk)),
        ]
        
        if hasattr(self, 'current_view_lib_id') and self.current_view_lib_id:
            items.append(ft.PopupMenuItem(
                content=ft.Text("Remove from Library", color=ft.Colors.RED_400),
                on_click=lambda _, trk=t, lid=self.current_view_lib_id: self._remove_track_confirm(lid, trk)
            ))
        
        menu = ft.PopupMenuButton(icon=ft.Icons.MORE_VERT, items=items)
        
        row = ft.Container(
            content=ft.Row([
                track_img,
                ft.Column([
                    ft.Row([
                        ft.Text(t.get("title"), weight="bold", size=16, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS, expand=True),
                        hires_badge
                    ], spacing=10),
                    ft.Text(t.get("artist"), size=14, color=ft.Colors.WHITE_30, max_lines=1)
                ], expand=True, spacing=4),
                ft.Row([
                    ft.IconButton(ft.Icons.ADD, icon_color=ft.Colors.WHITE_30, on_click=lambda _, trk=t: self._add_to_queue(trk)),
                    download_btn,  # NEW: Download button
                    ft.IconButton(ft.Icons.PLAY_ARROW_ROUNDED, icon_size=30, on_click=lambda _, idx=i, trks=tracks: self._play_track_from_list(trks, idx)),
                    menu
                ], spacing=0)
            ]),
            padding=12, border_radius=12,
            on_hover=lambda e: (setattr(e.control, "bgcolor", "#1A1A1A" if e.data == "true" else ft.Colors.TRANSPARENT), e.control.update() if e.control.page else None)
        )
        grid.controls.append(row)
        if t.get("albumCover"): self._load_art(t["albumCover"], track_img)
    
    self.viewport.controls.append(grid)
    self.page.update()


def _on_download_complete(self, track_id, success, message):
    """Handle download completion"""
    if success:
        self.page.snack_bar = ft.SnackBar(ft.Text(f"Download complete!"))
    else:
        self.page.snack_bar = ft.SnackBar(ft.Text(f"Download failed: {message}"))
    self.page.snack_bar.open = True
    self.page.update()


# Modify _play_track to check for local files first (around line 590)
def _play_track_with_local_check(self, track):
    """Play track - check local file first, then stream"""
    def _task():
        try:
            track_id = track.get("id")
            
            # Check if track is downloaded
            local_path = self.download_manager.get_local_path(track_id)
            
            if local_path:
                # Play from local file
                print(f"[Local Playback] Playing from: {local_path}")
                url = f"file:///{local_path}"
            else:
                # Stream from API
                print(f"[Stream Playback] Streaming track {track_id}")
                url = self.api.get_stream_url(track_id)
                if not url:
                    def _error():
                        self.page.snack_bar = ft.SnackBar(ft.Text("Failed to get stream URL"))
                        self.page.snack_bar.open = True
                        self.page.update()
                    self.page.run_thread(_error)
                    return
            
            self.player.play_url(url, track)
            
            # Add to play history
            if track not in self.play_history:
                self.play_history.insert(0, track)
                self.play_history = self.play_history[:5]
            
            # Update UI
            def _sync():
                try:
                    self.track_title.value = track.get("title")
                    self.track_artist.value = track.get("artist")
                    
                    q = track.get("audioQuality", {})
                    if q.get("isHiRes"):
                        self.audio_quality_info.value = f"{q.get('maximumBitDepth')}bit / {q.get('maximumSamplingRate')}kHz"
                        self.audio_quality_info.visible = True
                    else:
                        self.audio_quality_info.visible = False
                    
                    self.play_btn.icon = ft.Icons.PAUSE_CIRCLE_FILLED
                    self.lyrics_data = []
                    self.current_lyric_idx = -1
                    if track.get("albumCover"): self._load_art(track["albumCover"], self.track_art)
                    threading.Thread(target=self._fetch_lyrics, args=(track,), daemon=True).start()
                    self.page.update()
                except Exception as e:
                    print(f"UI Sync error: {e}")
            
            self.page.run_thread(_sync)
        except Exception as e:
            def _error():
                self.page.snack_bar = ft.SnackBar(ft.Text(f"Playback Error: {str(e)}"))
                self.page.snack_bar.open = True
                self.page.update()
            self.page.run_thread(_error)
            print(f"Playback task error: {e}")
    
    threading.Thread(target=_task, daemon=True).start()
