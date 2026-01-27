import flet as ft
import threading
import os
import re
import requests
import time
from io import BytesIO
from concurrent.futures import ThreadPoolExecutor
from functools import wraps
from dab_api import DabAPI
from player import AudioPlayer
from media_controls import MediaControls
from yt_api import YouTubeAPI
from settings import Settings
from download_manager import DownloadManager
# from windows_media import WindowsMediaControls
from dotenv import load_dotenv

# Hardcoded YouTube API Key for Build (NOT for Git)
YT_API_KEY = "youtube api key here"

if not YT_API_KEY or "AIza" not in YT_API_KEY:
    print("WARNING: YouTube API Key not found or invalid!")

# Performance Optimization Utilities
def debounce(wait_ms=300):
    """Debounce decorator to prevent rapid successive calls"""
    def decorator(func):
        func._debounce_timer = None
        func._debounce_lock = threading.Lock()
        
        @wraps(func)
        def wrapper(*args, **kwargs):
            def call_func():
                func(*args, **kwargs)
            
            with func._debounce_lock:
                if func._debounce_timer:
                    func._debounce_timer.cancel()
                func._debounce_timer = threading.Timer(wait_ms / 1000.0, call_func)
                func._debounce_timer.start()
        
        return wrapper
    return decorator

def throttle(wait_ms=100):
    """Throttle decorator to limit call frequency"""
    def decorator(func):
        func._last_call = 0
        func._lock = threading.Lock()
        
        @wraps(func)
        def wrapper(*args, **kwargs):
            now = time.time()
            with func._lock:
                if now - func._last_call >= wait_ms / 1000.0:
                    func._last_call = now
                    return func(*args, **kwargs)
        
        return wrapper
    return decorator

class DabFletApp:
    def __init__(self, page: ft.Page):
        self.page = page
        self.page.title = "BeatBoss Player (Mobile)"
        self.page.theme_mode = ft.ThemeMode.DARK
        self.page.bgcolor = "#020202"
        self.page.padding = 0
        self.page.spacing = 0
        self.page.window_width = 1350
        self.page.window_height = 900
        self.page.window_icon = "logo.png"
        
        # Logic Init
        self.settings = Settings()
        self.api = DabAPI(log_callback=self.add_debug_log)
        self.yt_api = YouTubeAPI(YT_API_KEY, log_callback=self.add_debug_log)
        self.download_manager = DownloadManager(self.settings, log_callback=self.add_debug_log)
        
        # Apply theme from settings
        theme = self.settings.get_theme()
        self.page.theme_mode = ft.ThemeMode.DARK if theme == "dark" else ft.ThemeMode.LIGHT
        if theme == "light":
            self.page.bgcolor = "#F5F5F5"  # Light gray background
        else:
            self.page.bgcolor = "#020202"  # Dark background
        
        # Audio Player Init
        self.player = AudioPlayer(self.page)
        self.player.on_track_end = self._next_track
        self.player.on_error = self._on_player_error
        
        # State
        self.current_retry_count = 0
        self.queue = []
        self.current_track_index = -1
        self.image_cache = {}
        self.lyrics_data = [] # List of (time_ms, text)
        self.current_lyric_idx = -1
        self.running = True
        self.view_stack = [] # To handle back navigation
        self.debug_logs = [] # List of log strings
        self.art_semaphore = threading.Semaphore(2) 
        self.shuffle_enabled = False
        self.loop_mode = "off"  # off, loop_one, loop_all
        self.original_queue = []
        self.recent_searches = self.settings.get_recent_searches()  # Load from settings
        self.play_history = self.settings.get_play_history()  # Load from settings
        self.current_view = "home"  # Track current view for toggle behavior
        self.last_search_results = []  # Cache search results for refresh
        
        # Library cache
        self.cached_libraries = None  # Cache library list
        self.library_last_updated = 0  # Timestamp of last library fetch
        self.current_lib_tracks = []  # Cache current library tracks for refresh
        
        # Pagination state
        self.current_lib_id = None
        self.current_lib_page = 1
        self.is_loading_more = False
        self.has_more_tracks = True
        
        # Theme colors
        self.current_theme = self.settings.get_theme()
        self._update_theme_colors()
        
        # Performance Optimization: Thread Pools
        self.thread_pool = ThreadPoolExecutor(max_workers=32, thread_name_prefix="worker")
        self.image_pool = ThreadPoolExecutor(max_workers=8, thread_name_prefix="image")
        self.active_futures = set()  # Track futures to cancel on view change
        self.futures_lock = threading.Lock() # Fix for "dictionary iteration changed" crash
        
        # Performance: Click guards and debouncing state
        self._view_switching = False
        self._last_view_switch = 0
        self._search_focused = False # Manual focus tracker for keyboard shortcuts
        self._pending_updates = set()  # Track which controls need updates
        self._update_batch_timer = None
        
        # View Caching for instant switching (RAM optimization)
        self.queue_view_cache = None
        self.lyrics_view_cache = None
        self.queue_cache_dirty = True  # Rebuild on next view
        self.lyrics_cache_dirty = True
        
        # Responsive UI state
        self.is_mobile_view = False
        self.page.on_resize = self._on_window_resize
        
        # Audio Player Init
        self._setup_ui()
        
        # Keyboard handling (Space to toggle)
        self.page.on_keyboard_event = self._on_keyboard
        # Mobile Back Button
        self.page.on_back_button_pressed = self._handle_back
        
        
        # Media Controls (keyboard hotkeys)
        self.media_controls = MediaControls(
            on_play_pause=self._toggle_playback,
            on_next=self._next_track,
            on_prev=self._prev_track
        )
        self.media_controls.start()
        
        # Windows Media Integration (SMTC) - Disabled for Flet Mobile
        # def _init_smtc():
        #     try:
        #         self.windows_media = WindowsMediaControls(
        #             on_play_pause=self._toggle_playback,
        #             on_next=self._next_track,
        #             on_prev=self._prev_track
        #         )
        #     except Exception as e:
        #         print(f"SMTC Init Error: {e}")
        #
        # threading.Thread(target=_init_smtc, daemon=True).start()
        
        # Start periodic download progress refresh
        self._start_download_refresh_timer()
        
        
        self.running = True
        threading.Thread(target=self._update_loop, daemon=True).start()
        
        # Auto-login check
        auth = self.settings.get_auth_credentials()
        if auth and auth.get("email") and auth.get("password"):
            # Delay slightly to ensure UI is ready
            threading.Timer(0.5, lambda: self._handle_login(auth["email"], auth["password"], is_auto=True)).start()
        else:
            self._show_home()

        # Check for missing API Key
        if not YT_API_KEY or "AIza" not in YT_API_KEY:
             threading.Timer(2.0, lambda: self._show_banner("Search disabled: YouTube API key missing in .env", ft.Colors.ORANGE_700)).start()

    def _update_loop(self):
        while self.running:
            try:
                # SAFETY: Check if session still exists before updating UI
                if not hasattr(self, 'page') or self.page is None:
                    break
                
                if self.player.is_playing:
                    cur = self.player.get_time()
                    dur = self.player.get_length()
                    if dur > 0:
                        prog = (cur / dur) * 1000
                        def _sync():
                            try:
                                self.seek_slider.value = prog
                                self.time_cur.value = self._format_ms(cur)
                                self.time_end.value = self._format_ms(dur)
                                
                                # Update mobile controls too
                                if hasattr(self, 'mobile_seek'):
                                    self.mobile_seek.value = prog
                                if hasattr(self, 'mobile_time_cur'):
                                    self.mobile_time_cur.value = self.time_cur.value
                                if hasattr(self, 'mobile_time_end'):
                                    self.mobile_time_end.value = self.time_end.value
                                
                                self._sync_lyrics(cur)
                                # Batch update only these controls
                                self.seek_slider.update()
                                self.time_cur.update()
                                self.time_end.update()
                                
                                # Update mobile UI elements
                                if hasattr(self, 'mobile_seek') and self.mobile_seek.page:
                                    self.mobile_seek.update()
                                if hasattr(self, 'mobile_time_cur') and self.mobile_time_cur.page:
                                    self.mobile_time_cur.update()
                                if hasattr(self, 'mobile_time_end') and self.mobile_time_end.page:
                                    self.mobile_time_end.update()
                                    
                                # Sync playback icons if they drifted
                                player_is_playing = self.player.is_playing
                                ui_is_playing = (self.play_btn.icon == ft.Icons.PAUSE_CIRCLE_FILLED)
                                if player_is_playing != ui_is_playing:
                                    self._update_playback_ui(player_is_playing)
                            except:
                                pass
                        
                        # SAFETY: Check session before calling run_thread
                        try:
                            if hasattr(self.page, 'session') and self.page.session:
                                self.page.run_thread(_sync)
                        except (RuntimeError, AttributeError):
                            # Session destroyed, stop the loop
                            break
            except Exception as e:
                print(f"Update loop error: {e}")
                # Continue running even if one iteration fails
            
            # Much slower updates for better performance (was 0.3-0.8s, now 1s)
            time.sleep(1.0)

    def _sync_lyrics(self, cur_ms):
        if not self.lyrics_data or not hasattr(self, 'lyrics_scroll'): return
        # Find current lyric index
        idx = -1
        for i, (t, _) in enumerate(self.lyrics_data):
            if cur_ms >= t:
                idx = i
            else:
                break
        
        if idx != self.current_lyric_idx and idx != -1:
            self.current_lyric_idx = idx
            def _update_ui():
                # Highlight lyric in UI (ALWAYS do this first)
                if hasattr(self, 'lyrics_scroll') and self.lyrics_scroll and self.lyrics_scroll.controls:
                    for i, lyric_row in enumerate(self.lyrics_scroll.controls):
                        try:
                            if i == idx:
                                active_color = ft.Colors.GREEN_700 if self.current_theme == "light" else ft.Colors.GREEN
                                lyric_row.content.color = active_color
                                lyric_row.content.size = 28
                                lyric_row.content.weight = "bold"
                            else:
                                lyric_row.content.color = self._get_secondary_color()
                                lyric_row.content.size = 22
                                lyric_row.content.weight = "normal"
                        except:
                            pass  # Continue even if one lyric fails
                    
                    # WINDOWED KARAOKE APPROACH: Show only a small window of lyrics
                    # Like real karaoke: 2 before, current (3rd line), 3 after
                    try:
                        # Define window size (3rd line centered)
                        lines_before = 2  # Changed from 3 to center on 3rd line
                        lines_after = 3
                        
                        # Calculate window range
                        start_idx = max(0, idx - lines_before)
                        end_idx = min(len(self.lyrics_data), idx + lines_after + 1)
                        
                        # Only rebuild if window changed (smoother transitions)
                        current_window = (start_idx, end_idx)
                        if not hasattr(self, '_last_lyrics_window') or self._last_lyrics_window != current_window:
                            self._last_lyrics_window = current_window
                            
                            # Clear and rebuild with just visible window
                            self.lyrics_scroll.controls.clear()
                            
                            # Show only the visible window (no top padding)
                            for i in range(start_idx, end_idx):
                                _, text = self.lyrics_data[i]
                                
                                # Determine color and size
                                if i == idx:
                                    color = ft.Colors.GREEN_700 if self.current_theme == "light" else ft.Colors.GREEN
                                    size = 28
                                    weight = "bold"
                                else:
                                    color = self._get_secondary_color()
                                    size = 22
                                    weight = "normal"
                                
                                lyric_container = ft.Container(
                                    content=ft.Text(
                                        text, 
                                        size=size, 
                                        color=color, 
                                        weight=weight,
                                        text_align=ft.TextAlign.CENTER
                                    ),
                                    padding=ft.Padding(top=15, bottom=15, left=20, right=20),
                                )
                                self.lyrics_scroll.controls.append(lyric_container)
                        else:
                            # Window same, just update colors (much faster, smoother)
                            for i, lyric_row in enumerate(self.lyrics_scroll.controls):
                                actual_idx = start_idx + i
                                if actual_idx == idx:
                                    lyric_row.content.color = ft.Colors.GREEN_700 if self.current_theme == "light" else ft.Colors.GREEN
                                    lyric_row.content.size = 28
                                    lyric_row.content.weight = "bold"
                                else:
                                    lyric_row.content.color = self._get_secondary_color()
                                    lyric_row.content.size = 22
                                    lyric_row.content.weight = "normal"
                        
                        self.lyrics_scroll.update()
                                
                    except Exception as e:
                        print(f"Windowed lyrics error: {e}")
            
            # SAFETY: Check session before updating
            try:
                if hasattr(self, 'page') and hasattr(self.page, 'session') and self.page.session:
                    self.page.run_thread(_update_ui)
            except (RuntimeError, AttributeError):
                pass  # Session destroyed, skip update

    def _format_ms(self, ms):
        s = int(ms / 1000)
        m, s = divmod(s, 60)
        return f"{m}:{s:02d}"

    def add_debug_log(self, method, url, status, body=None):
        log_entry = f"[{method}] {url} -> {status}"
        self.debug_logs.append(log_entry)
        print(log_entry)
        if hasattr(self, "log_col") and self.log_col:
            self.log_col.controls.append(ft.Text(log_entry, font_family="Consolas", size=12, color=ft.Colors.GREEN_400))
            self.page.update()

    def _show_monitor(self):
        self.log_col = ft.Column(scroll=ft.ScrollMode.ADAPTIVE, expand=True)
        for log in self.debug_logs:
            self.log_col.controls.append(ft.Text(log, font_family="Consolas", size=12, color=ft.Colors.GREEN_400))
            
        dlg = ft.AlertDialog(
            title=ft.Text("DAB API Monitor"),
            content=ft.Container(content=self.log_col, width=800, height=400, bgcolor="#050505", padding=10),
            actions=[ft.TextButton("Clear", on_click=lambda _: self._clear_logs()), ft.TextButton("Close", on_click=lambda e: self._close_dlg(e.control))]
        )
        self.page.dialog = dlg
        dlg.open = True
        self.page.update()

    def _clear_logs(self):
        self.debug_logs = []
        if self.log_col:
            self.log_col.controls.clear()
            self.page.update()

    def _close_dlg(self, btn):
        btn.parent.open = False 
        self.page.update()

    def _assign_ref(self, name):
        """Assign a reference to a class attribute"""
        ref = ft.Ref()
        setattr(self, name, ref)
        return ref

    def _create_player_track_info(self):
        """Create the left section of player bar (track info) - saved as self.player_track_info"""
        self.player_track_info = ft.Row([
            self.track_art,
            ft.Column([
                self.track_title,
                ft.Row([self.track_artist, self.audio_quality_info], spacing=10)
            ], spacing=2, alignment=ft.MainAxisAlignment.CENTER)
        ], spacing=15, width=280)
        return self.player_track_info

    def _create_player_controls(self):
        """Create the center section of player bar (controls) - saved as self.player_center"""
        self.seek_container = ft.Container(
            content=ft.Row([
                self.time_cur,
                self.seek_slider,
                self.time_end
            ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER),
            width=550,
            margin=ft.Margin(0, -25, 0, 0)
        )
        self.player_center = ft.Column([
            ft.Row([
                self.shuffle_btn,
                ft.IconButton(ft.Icons.SKIP_PREVIOUS, icon_size=24, icon_color=ft.Colors.WHITE, on_click=lambda _: self._prev_track(), ref=self._assign_ref("btn_prev")),
                self.play_btn,
                ft.IconButton(ft.Icons.SKIP_NEXT, icon_size=24, icon_color=ft.Colors.WHITE, on_click=lambda _: self._next_track(), ref=self._assign_ref("btn_next")),
                self.repeat_btn,
            ], alignment=ft.MainAxisAlignment.CENTER, spacing=10),
            self.seek_container
        ], alignment=ft.MainAxisAlignment.CENTER, horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=2, expand=True)
        return self.player_center

    def _create_player_extras(self):
        """Create the right section of player bar (volume/extras) - saved as self.player_extras"""
        self.player_extras = ft.Row([
            ft.IconButton(ft.Icons.LYRICS, icon_size=20, icon_color=ft.Colors.WHITE_30, on_click=lambda _: self._show_lyrics_view(), tooltip="Toggle Lyrics", ref=self._assign_ref("btn_lyrics")),
            ft.IconButton(ft.Icons.QUEUE_MUSIC, icon_size=20, icon_color=ft.Colors.WHITE_30, on_click=lambda _: self._show_queue(), tooltip="Show Queue", ref=self._assign_ref("btn_queue")),
            ft.IconButton(ft.Icons.VOLUME_UP, icon_size=20, icon_color=ft.Colors.WHITE_30, ref=self._assign_ref("btn_vol")),
            self.vol_slider,
        ], spacing=5, alignment=ft.MainAxisAlignment.END, width=320)
        return self.player_extras

    def _setup_ui(self):
        # 1. Sidebar Widgets
        # Hamburger button for mobile sidebar toggle (inside sidebar)
        self.hamburger_btn = ft.IconButton(
            ft.Icons.MENU, 
            icon_size=28, 
            icon_color=ft.Colors.GREEN,
            on_click=lambda _: self._toggle_sidebar(),
            visible=False  # Hidden on desktop
        )
        
        # Initialize Player Buttons
        self.mobile_play_btn = ft.IconButton(
            ft.Icons.PLAY_CIRCLE_FILLED, 
            icon_size=36, 
            icon_color=ft.Colors.WHITE, 
            on_click=lambda _: self._toggle_playback()
        )
        self.mobile_prev_btn = ft.IconButton(
            ft.Icons.SKIP_PREVIOUS, 
            icon_size=24, 
            icon_color=ft.Colors.WHITE, 
            on_click=lambda _: self._prev_track()
        )
        self.mobile_shuffle_btn = ft.IconButton(
            ft.Icons.SHUFFLE, 
            icon_size=18, 
            icon_color=ft.Colors.WHITE_30, 
            on_click=lambda _: self._toggle_shuffle()
        )
        self.mobile_repeat_btn = ft.IconButton(
            ft.Icons.REPEAT, 
            icon_size=18, 
            icon_color=ft.Colors.WHITE_30, 
            on_click=lambda _: self._toggle_loop()
        )
        
        # Mini controls for collapsed mobile state
        self.mini_play_btn = ft.IconButton(
            ft.Icons.PAUSE_CIRCLE_FILLED,
            icon_size=32,
            icon_color=ft.Colors.WHITE,
            on_click=lambda _: self._toggle_playback()
        )
        self.mini_next_btn = ft.IconButton(
            ft.Icons.SKIP_NEXT,
            icon_size=28,
            icon_color=ft.Colors.WHITE,
            on_click=lambda _: self._next_track()
        )
        self.collapse_btn = ft.IconButton(
            ft.Icons.KEYBOARD_ARROW_DOWN,
            icon_size=24,
            icon_color=ft.Colors.WHITE_30,
            on_click=lambda _: self._toggle_mobile_player(),
            padding=0,
            tooltip="Collapse Player"
        )
        self.expand_btn = ft.IconButton(
            ft.Icons.KEYBOARD_ARROW_UP,
            icon_size=24,
            icon_color=ft.Colors.WHITE_30,
            on_click=lambda _: self._toggle_mobile_player(),
            visible=False,
            tooltip="Expand Player"
        )
        self.player_expanded = True
        
        # Logo row with hamburger
        self.logo_row = ft.Row([
            ft.Icon(ft.Icons.MUSIC_NOTE, color=ft.Colors.GREEN, size=32),
            ft.Text("BeatBoss", size=24, weight="bold")
        ], alignment=ft.MainAxisAlignment.START)
        
        self.sidebar_content = ft.Column([
            self.hamburger_btn,  # Hamburger at top (visible only on mobile)
            self.logo_row,
            ft.Container(height=30),
            self._nav_item(ft.Icons.HOME, "Home", self._show_home, True),
            self._nav_item(ft.Icons.SEARCH, "Search", self._show_search),
            self._nav_item(ft.Icons.LIBRARY_MUSIC, "Library", self._show_library),
            ft.Divider(height=30),
            self._nav_item(ft.Icons.ADD_BOX, "Create Library", self._open_create_lib),
            self._nav_item(ft.Icons.FAVORITE, "Liked Songs", self._show_favorites),
            self._nav_item(ft.Icons.SETTINGS, "Settings", self._show_settings),
            ft.Container(height=15),
            self._nav_item(ft.Icons.LOGOUT, "Sign Out", self._handle_logout, color=ft.Colors.RED_400),
        ], spacing=5, horizontal_alignment=ft.CrossAxisAlignment.START)  # Left-aligned by default

        self.sidebar = ft.Container(
            width=260,
            bgcolor=self.sidebar_bg,
            padding=ft.Padding(20, 20, 20, 20),
            content=self.sidebar_content
        )

        # 2. Main Viewport Widgets
        self.search_bar = ft.TextField(
            hint_text="Search tracks, artists...",
            prefix_icon=ft.Icons.SEARCH,
            border_radius=25,
            border_color=ft.Colors.TRANSPARENT,
            focused_border_color=ft.Colors.GREEN,
            height=45,
            content_padding=10,
            expand=True,
            on_submit=lambda e: self.page.run_thread(self._handle_search),
            on_focus=lambda _: setattr(self, "_search_focused", True),
            on_blur=lambda _: setattr(self, "_search_focused", False)
        )
        
        # Unify: Search icon button for mobile is no longer needed if bar is default
        self.search_icon_btn = ft.IconButton(
            ft.Icons.SEARCH,
            icon_size=28,
            icon_color=ft.Colors.WHITE,
            on_click=lambda _: self.search_bar.focus(),
            visible=False 
        )
        
        # Unify: Replaced by single search_bar
        self.mobile_search_bar = self.search_bar
        
        # Close search button - no longer needed
        self.close_search_btn = ft.IconButton(
            ft.Icons.CLOSE,
            icon_size=20,
            icon_color=ft.Colors.WHITE,
            visible=False
        )
        
        # Import button
        self.import_btn = ft.Container(
            content=ft.Row([
                ft.Icon(ft.Icons.IMPORT_EXPORT, size=18, color=ft.Colors.BLACK),
                ft.Text("IMPORT", weight="bold", color=ft.Colors.BLACK)
            ]),
            bgcolor=ft.Colors.GREEN,
            padding=ft.Padding(left=20, top=10, right=20, bottom=10),
            border_radius=25,
            on_click=lambda _: self._open_import()
        )
        
        # Desktop search row (full search bar + import)
        self.search_row_desktop = ft.Row([
            self.search_bar,
            ft.Container(width=20),
            self.import_btn
        ])
        
        # Mobile search row (search icon + import, or expanded search bar)
        self.search_row_mobile = ft.Row([
            self.mobile_search_bar,
            self.close_search_btn,
            self.search_icon_btn,
            self.import_btn
        ], visible=False)

        self.viewport = ft.Column(expand=True, scroll=ft.ScrollMode.ADAPTIVE)
        
        self.main_container = ft.Container(
            expand=True,
            bgcolor=self.viewport_bg,
            padding=ft.Padding(left=40, top=30, right=40, bottom=20),
            content=ft.Column([
                ft.Row([
                    self.search_bar,
                    ft.Container(width=20),
                    self.import_btn
                ]),
                ft.Container(height=20),
                self.viewport
            ])
        )

        # 3. Player Bar Widgets
        self.track_art_img = ft.Container(width=60, height=60, bgcolor="#1A1A1A", border_radius=10)
        self.track_art_tick = ft.Icon(ft.Icons.CHECK_CIRCLE, color=ft.Colors.GREEN, size=18, visible=False)
        self.track_art = ft.Stack([
            self.track_art_img,
            ft.Container(content=self.track_art_tick, bottom=-2, right=-2, bgcolor=ft.Colors.with_opacity(0.8, "#020202"), border_radius=10, padding=2)
        ], width=60, height=60)

        self.track_title = ft.Text("Ambient Silence", size=14, weight="bold")
        self.track_artist = ft.Text("Start your journey", size=12, color=self._get_secondary_color())
        
        
        self.play_btn = ft.IconButton(ft.Icons.PLAY_CIRCLE_FILLED, icon_size=48, icon_color=ft.Colors.WHITE, on_click=lambda _: self._toggle_playback())
        self.shuffle_btn = ft.IconButton(ft.Icons.SHUFFLE, icon_size=18, icon_color=ft.Colors.WHITE_30, on_click=lambda _: self._toggle_shuffle())
        self.repeat_btn = ft.IconButton(ft.Icons.REPEAT, icon_size=18, icon_color=ft.Colors.WHITE_30, on_click=lambda _: self._toggle_loop())
        
        # Audio Quality Info (Hi-Res)
        self.audio_quality_info = ft.Text("", size=10, color=ft.Colors.GREEN_400, weight="bold")
        
        self.time_cur = ft.Text("0:00", size=11, color=ft.Colors.WHITE_30)
        self.seek_slider = ft.Slider(
            min=0, 
            max=1000, 
            expand=True, 
            active_color=ft.Colors.GREEN, 
            inactive_color=ft.Colors.WHITE_10,
            on_change=lambda e: self._on_seek(e.control.value)
        )
        self.time_end = ft.Text("0:00", size=11, color=ft.Colors.WHITE_30)
        
        self.vol_slider = ft.Slider(width=100, value=80, min=0, max=100, active_color=ft.Colors.GREEN, on_change=lambda e: self.player.set_volume(e.control.value))

        # Create player bar sections
        self._create_player_track_info()
        self._create_player_controls()
        self._create_player_extras()
        
        # Desktop player bar content (horizontal)
        self.player_bar_desktop = ft.Row([
            self.player_track_info,
            self.player_center,
            self.player_extras
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)
        
        # Mobile player bar content (compact 2-row layout)
        # Row 1: Track info + controls
        self.mobile_track_title = ft.Text("No track", size=12, weight="bold", no_wrap=True, width=120)
        self.mobile_track_artist = ft.Text("", size=10, color=ft.Colors.WHITE_54, no_wrap=True, width=120)
        
        self.mobile_track_art_img = ft.Container(width=45, height=45, border_radius=5, bgcolor="#1A1A1A")
        self.mobile_track_art_tick = ft.Icon(ft.Icons.CHECK_CIRCLE, color=ft.Colors.GREEN, size=14, visible=False)
        self.mobile_track_art = ft.Stack([
            self.mobile_track_art_img,
            ft.Container(content=self.mobile_track_art_tick, bottom=-2, right=-2, bgcolor=ft.Colors.with_opacity(0.8, "#020202"), border_radius=7, padding=1)
        ], width=45, height=45)
        
        self.mobile_time_cur = ft.Text("0:00", size=9, color=ft.Colors.WHITE_30)
        self.mobile_time_end = ft.Text("0:00", size=9, color=ft.Colors.WHITE_30)
        self.mobile_seek = ft.Slider(
            min=0, 
            max=1000, 
            expand=True, 
            active_color=ft.Colors.GREEN, 
            inactive_color=ft.Colors.WHITE_10, 
            on_change=lambda e: self._on_seek(e.control.value)
        )

        # Sub-containers for visibility toggling
        self.mobile_seek_row = ft.Row([
            self.mobile_time_cur,
            self.mobile_seek,
            self.mobile_time_end,
        ], spacing=5, vertical_alignment=ft.CrossAxisAlignment.CENTER)
        
        self.mobile_controls_row = ft.Row([
            ft.Row([self.mobile_shuffle_btn, self.mobile_repeat_btn], spacing=0),
            ft.Row([
                self.mobile_prev_btn,
                self.mobile_play_btn,
                ft.IconButton(ft.Icons.SKIP_NEXT, icon_size=28, icon_color=ft.Colors.WHITE, on_click=lambda _: self._next_track()),
            ], spacing=10),
            ft.Row([
                ft.IconButton(ft.Icons.LYRICS, icon_size=20, icon_color=ft.Colors.WHITE_30, on_click=lambda _: self._show_lyrics_view(), tooltip="Toggle Lyrics"),
                ft.IconButton(ft.Icons.QUEUE_MUSIC, icon_size=20, icon_color=ft.Colors.WHITE_30, on_click=lambda _: self._show_queue(), tooltip="Show Queue"),
            ], spacing=0),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)

        self.mobile_mini_controls = ft.Row([
            self.mini_play_btn,
            self.mini_next_btn,
            self.expand_btn  # Only shows when collapsed
        ], spacing=0, visible=False)

        # Minimise label + icon row
        self.minimise_controls = ft.Row([
            ft.Text("Minimise", size=12, color=ft.Colors.WHITE_30),
            self.collapse_btn
        ], spacing=5, visible=True)

        # Metadata row now handles its own toggle button for space efficiency
        # Metadata row simplification - toggle visibility of control sets
        self.mobile_metadata_row = ft.Row([
            ft.Row([
                self.mobile_track_art,
                ft.Column([
                    self.mobile_track_title,
                    self.mobile_track_artist
                ], spacing=0, alignment=ft.MainAxisAlignment.CENTER),
            ], spacing=10, expand=True),
            # Show either mini-controls or minimise label depending on state
            self.mobile_mini_controls,
            self.minimise_controls,
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN)

        self.player_bar_mobile = ft.Column([
            self.mobile_seek_row,
            self.mobile_controls_row,
            self.mobile_metadata_row,
        ], spacing=5, alignment=ft.MainAxisAlignment.END, visible=False)

        self.player_bar = ft.Container(
            height=90,
            bgcolor=ft.Colors.with_opacity(0.9, self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A"),
            blur=ft.Blur(20, 20),
            border=ft.Border(top=ft.BorderSide(0.5, ft.Colors.WHITE_10)),
            padding=ft.Padding(30, 0, 30, 0),
            content=ft.Stack([
                self.player_bar_desktop,
                self.player_bar_mobile
            ])
        )

        self.page.add(
            ft.Column([
                ft.Row([self.sidebar, self.main_container], expand=True, spacing=0),
                self.player_bar
            ], expand=True, spacing=0)
        )
        self._update_player_bar_theme()

    def _nav_item(self, icon, text, cmd, selected=False, color=None):
        def _on_click(e):
            def _nav():
                # Update all nav items to unselected
                for item in self.sidebar_content.controls:
                    if isinstance(item, ft.Container) and hasattr(item, "data"):
                        if item.data == "nav":
                            item.content.controls[0].color = None
                            item.content.controls[1].color = None
                            item.bgcolor = ft.Colors.TRANSPARENT
                
                e.control.content.controls[0].color = ft.Colors.GREEN
                e.control.content.controls[1].color = ft.Colors.GREEN
                e.control.bgcolor = ft.Colors.with_opacity(0.1, ft.Colors.GREEN)
                
                try:
                    e.control.update()
                except:
                    self.page.update()
                
                if cmd: cmd()
            
            self._safe_navigate(_nav)

        item = ft.Container(
            data="nav",
            content=ft.Row([
                ft.Icon(icon, color=color or (ft.Colors.GREEN if selected else None), size=20),
                ft.Text(text, color=color or (ft.Colors.GREEN if selected else None), weight="bold", size=14)
            ], alignment=ft.MainAxisAlignment.START),  # Left alignment for all sidebar content
            padding=ft.Padding(left=18, top=12, right=15, bottom=12),  # Refined left padding
            border_radius=10,
            bgcolor=ft.Colors.with_opacity(0.1, ft.Colors.GREEN) if selected else ft.Colors.TRANSPARENT,
            on_click=_on_click,
            on_hover=self._on_nav_hover
        )
        return item

    def _add_future(self, future):
        """Add a future to tracking and setup auto-removal on completion"""
        with self.futures_lock:
            self.active_futures.add(future)
        
        def _cleanup(f):
            try:
                with self.futures_lock:
                    self.active_futures.discard(f)
            except:
                pass
                
        future.add_done_callback(_cleanup)

    def _cancel_pending_operations(self):
        """Cancel all pending futures from previous view"""
        with self.futures_lock:
            snapshot = list(self.active_futures)
            self.active_futures.clear()
            
        for future in snapshot:
            if not future.done():
                future.cancel()

    def _safe_navigate(self, cmd):
        """Standardized navigation wrapper with locking and cleanup"""
        if self._view_switching:
            return
        
        self._view_switching = True
        self._cancel_pending_operations()
        
        def _task():
            try:
                cmd()
            except Exception as e:
                print(f"Navigation error: {e}")
            finally:
                self._view_switching = False
                
        self._add_future(self.thread_pool.submit(_task))

    def _on_nav_hover(self, e):
        # PERFORMANCE: Throttle hover events - only update every 100ms
        now = time.time()
        if not hasattr(self, '_last_hover_update'):
            self._last_hover_update = 0
        
        if now - self._last_hover_update < 0.1:  # 100ms throttle
            return
        self._last_hover_update = now
        
        # Only hover if not selected (check bgcolor for green)
        if e.control.bgcolor != ft.Colors.with_opacity(0.1, ft.Colors.GREEN):
            if e.data == "true":
                e.control.bgcolor = ft.Colors.with_opacity(0.1, ft.Colors.WHITE)
            else:
                e.control.bgcolor = ft.Colors.TRANSPARENT
            
            # PERFORMANCE: Update only this control, not entire page
            try:
                e.control.update()
            except:
                pass  # Silently fail if control not attached

    def _on_window_resize(self, e):
        """Handle window resize for responsive layout"""
        try:
            width = self.page.width or 1350
            is_mobile = width < 600
            
            # Update if mobile state changes OR if desktop width crosses expansion threshold (1000)
            crossing_threshold = (width >= 1000 and getattr(self, "_last_width", 1000) < 1000) or \
                                 (width < 1000 and getattr(self, "_last_width", 1000) >= 1000)
            
            if is_mobile != self.is_mobile_view or crossing_threshold:
                self.is_mobile_view = is_mobile
                self._update_responsive_layout()
            
            self._last_width = width
        except Exception as ex:
            print(f"Resize handler error: {ex}")

    def _update_responsive_layout(self):
        """Update layout based on screen width"""
        try:
            if self.is_mobile_view:
                # Mobile layout: narrow sidebar (icons only)
                self.sidebar.width = 70
                self.sidebar.padding = ft.Padding(10, 15, 10, 15)
                
                # Hide text labels in sidebar
                for item in self.sidebar_content.controls:
                    if isinstance(item, ft.Container) and hasattr(item, "data") and item.data == "nav":
                        if len(item.content.controls) > 1:
                            item.content.controls[1].visible = False
                
                # Hide logo text, show hamburger
                if hasattr(self, 'logo_row') and len(self.logo_row.controls) > 1:
                    self.logo_row.controls[1].visible = False
                if hasattr(self, 'hamburger_btn'):
                    self.hamburger_btn.visible = True
                
                # Left-align sidebar icons when collapsed
                self.sidebar_content.horizontal_alignment = ft.CrossAxisAlignment.START
                self.sidebar.visible = True
                
                # Reduce main container padding
                self.main_container.padding = ft.Padding(left=15, top=15, right=15, bottom=10)
                
                # Mobile player bar (max elevation and click safety)
                self.player_bar.height = 175 if self.player_expanded else 30
                self.player_bar.padding = ft.Padding(15, 5, 15, 30) if self.player_expanded else ft.Padding(15, 5, 15, 5)
                
                # Tighten column spacing
                if hasattr(self, 'player_bar_mobile'):
                    self.player_bar_mobile.spacing = 5
                
                # Toggle player bar layouts
                if hasattr(self, 'player_bar_desktop'):
                    self.player_bar_desktop.visible = False
                if hasattr(self, 'player_bar_mobile'):
                    self.player_bar_mobile.visible = True
                
            else:
                # Desktop layout: full sidebar
                self.sidebar.width = 260
                self.sidebar.padding = ft.Padding(20, 20, 20, 20)
                self.sidebar.visible = True
                
                # Show search bar and search button as default
                if hasattr(self, 'search_bar'):
                    self.search_bar.visible = True
                    self.search_bar.update()

                # Left-align sidebar items when expanded
                self.sidebar_content.horizontal_alignment = ft.CrossAxisAlignment.START
                
                # Show text labels in sidebar
                for item in self.sidebar_content.controls:
                    if isinstance(item, ft.Container) and hasattr(item, "data") and item.data == "nav":
                        if len(item.content.controls) > 1:
                            item.content.controls[1].visible = True
                
                # Show logo text, hide hamburger
                if hasattr(self, 'logo_row') and len(self.logo_row.controls) > 1:
                    self.logo_row.controls[1].visible = True
                if hasattr(self, 'hamburger_btn'):
                    self.hamburger_btn.visible = False
                
                # Restore main container padding
                self.main_container.padding = ft.Padding(left=40, top=30, right=40, bottom=20)
                
                # Desktop player bar
                self.player_bar.height = 90
                self.player_bar.padding = ft.Padding(30, 0, 30, 0)
                
                # Toggle player bar layouts
                if hasattr(self, 'player_bar_desktop'):
                    self.player_bar_desktop.visible = True
                if hasattr(self, 'player_bar_mobile'):
                    self.player_bar_mobile.visible = False
                
                # Show all desktop controls
                if hasattr(self, 'player_extras'):
                    self.player_extras.visible = True
                if hasattr(self, 'seek_container'):
                    self.seek_container.visible = True
                    self.seek_container.width = 550
                if hasattr(self, 'shuffle_btn'):
                    self.shuffle_btn.visible = True
                if hasattr(self, 'repeat_btn'):
                    self.repeat_btn.visible = True
                if hasattr(self, 'player_track_info'):
                    self.player_track_info.width = 280
            
            # Enforce Consistent Global Sidebar Rules
            self.sidebar.visible = True # Always visible
            
            if self.is_mobile_view or self.page.width < 1000:
                # Slim / Narrow View
                self.sidebar.width = 70
                self.sidebar.padding = ft.padding.all(10)
                self.sidebar_content.horizontal_alignment = ft.CrossAxisAlignment.CENTER # Centered icons for narrow
                
                for item in self.sidebar_content.controls:
                    if isinstance(item, ft.Container) and hasattr(item, "data") and item.data == "nav":
                         # Hide text labels
                         if len(item.content.controls) > 1:
                              item.content.controls[1].visible = False
                         # Center the row content itself
                         item.content.alignment = ft.MainAxisAlignment.CENTER
                         item.padding = ft.padding.symmetric(horizontal=0, vertical=12)
                
                # Align Logo and Hamburger in center
                if hasattr(self, 'logo_row'):
                     self.logo_row.alignment = ft.MainAxisAlignment.CENTER
                     if len(self.logo_row.controls) > 1:
                          self.logo_row.controls[1].visible = False
            else:
                # Expanded / Wide Desktop View
                self.sidebar.width = 260
                self.sidebar.padding = ft.Padding(20, 20, 20, 20)
                self.sidebar_content.horizontal_alignment = ft.CrossAxisAlignment.START # Left aligned content
                
                for item in self.sidebar_content.controls:
                    if isinstance(item, ft.Container) and hasattr(item, "data") and item.data == "nav":
                         # Show text labels
                         if len(item.content.controls) > 1:
                              item.content.controls[1].visible = True
                         # Left-align the row
                         item.content.alignment = ft.MainAxisAlignment.START
                         item.padding = ft.padding.only(left=18, top=12, right=15, bottom=12)

                # Align Logo and Hamburger left
                if hasattr(self, 'logo_row'):
                     self.logo_row.alignment = ft.MainAxisAlignment.START
                     if len(self.logo_row.controls) > 1:
                          self.logo_row.controls[1].visible = True
            
            self.main_container.padding = 10 if self.is_mobile_view else 30
            self.viewport.spacing = 15 if self.is_mobile_view else 25
            
            self.page.update()
        except Exception as ex:
            print(f"Responsive layout error: {ex}")

    def _toggle_sidebar(self):
        """Toggle sidebar expansion on mobile (hamburger menu)"""
        try:
            if self.sidebar.width == 70:
                # Expand sidebar
                self.sidebar.width = 260
                self.sidebar.padding = ft.Padding(20, 20, 20, 20)
                
                # Show text labels
                for item in self.sidebar_content.controls:
                    if isinstance(item, ft.Container) and hasattr(item, "data") and item.data == "nav":
                        if len(item.content.controls) > 1:
                            item.content.controls[1].visible = True
                
                # Show logo text
                if hasattr(self, 'logo_row') and len(self.logo_row.controls) > 1:
                    self.logo_row.controls[1].visible = True
            else:
                # Collapse sidebar
                self.sidebar.width = 70
                self.sidebar.padding = ft.Padding(10, 20, 10, 20)
                
                # Hide text labels
                for item in self.sidebar_content.controls:
                    if isinstance(item, ft.Container) and hasattr(item, "data") and item.data == "nav":
                        if len(item.content.controls) > 1:
                            item.content.controls[1].visible = False
                
                # Hide logo text
                if hasattr(self, 'logo_row') and len(self.logo_row.controls) > 1:
                    self.logo_row.controls[1].visible = False
            
            self.page.update()
        except Exception as ex:
            print(f"Toggle sidebar error: {ex}")

    def _expand_search(self):
        """No longer used with unified search bar"""
        pass

    def _collapse_search(self):
        """No longer used with unified search bar"""
        pass

    def _show_search(self):
        self.view_stack.clear() # Clear history on top-level nav
        self.current_view = "search"
        self.viewport.controls.clear()
        self.viewport.controls.append(ft.Text("Search", size=32, weight="bold"))
        self.viewport.controls.append(ft.Text("Find your next favorite track"))
        self.viewport.controls.append(ft.Container(height=20))
        
        # Recent Searches
        if self.recent_searches:
            self.viewport.controls.append(ft.Text("Recent Searches", size=16))
            self.viewport.controls.append(ft.Container(height=10))
            for search_term in self.recent_searches:
                search_chip = ft.Container(
                    content=ft.Text(search_term, size=14),
                    bgcolor=self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A",
                    padding=ft.Padding(15, 10, 15, 10),
                    border_radius=20,
                    on_click=lambda _, term=search_term: (setattr(self.search_bar, 'value', term), self.page.run_thread(self._handle_search))
                )
                self.viewport.controls.append(search_chip)
        else:
            self.viewport.controls.append(ft.Text("No recent searches", size=14, color=ft.Colors.WHITE_30))
        
        self.page.update()

    def _show_home(self):
        self.view_stack.clear() # Clear history on top-level nav
        self.current_view = "home"
        self.viewport.controls.clear()
        self.viewport.controls.append(ft.Text("Discover Music", size=48, weight="bold"))
        
        # Show personalized welcome if logged in
        if self.api.user:
            username = self.api.user.get('username', 'User')
            self.viewport.controls.append(ft.Text(f"Welcome back, {username}", color=ft.Colors.WHITE_30, size=18))
        else:
            self.viewport.controls.append(ft.Text("Welcome to BeatBoss", color=ft.Colors.WHITE_30, size=18))
        
        if not self.api.user:
            self._draw_login()
        else:
            self.viewport.controls.append(ft.Text(f"Hello", color=ft.Colors.GREEN))
            
            # Recently Played
            if self.play_history:
                self.viewport.controls.append(ft.Container(height=40))
                self.viewport.controls.append(ft.Text("Recently Played", size=24, weight="bold"))
                self.viewport.controls.append(ft.Container(height=15))
                # Display last 5 played tracks
                self._display_tracks(self.play_history[:5])
        self.page.update()

    def _draw_login(self, is_signup=False):
        self.viewport.controls.clear()
        
        # Responsive width calculation
        card_width = min(400, self.page.width - 40) if self.page.width > 0 else 380
        
        self.login_email = ft.TextField(label="Email", border_radius=15, border_color=ft.Colors.OUTLINE)
        self.login_pass = ft.TextField(label="Password", password=True, can_reveal_password=True, border_radius=15, border_color=ft.Colors.OUTLINE)
        self.login_name = ft.TextField(label="Username", border_radius=15, border_color=ft.Colors.OUTLINE) if is_signup else None
        
        controls = [
            ft.Icon(ft.Icons.MUSIC_NOTE, size=48, color=ft.Colors.GREEN),
            ft.Text("Create Account" if is_signup else "Welcome to BeatBoss", size=24, weight="bold", text_align=ft.TextAlign.CENTER),
            ft.Text("Powered by DAB", size=12) if not is_signup else ft.Container(height=0),
            ft.Container(height=20),
        ]
        
        if is_signup:
            controls.append(self.login_name)
        
        controls.extend([
            self.login_email,
            self.login_pass,
            ft.Container(height=20),
            ft.FilledButton(
                "SIGN UP" if is_signup else "SIGN IN", 
                width=card_width - 40, height=50, 
                style=ft.ButtonStyle(bgcolor=ft.Colors.GREEN, color=ft.Colors.BLACK, shape=ft.RoundedRectangleBorder(radius=15)), 
                on_click=lambda _: self._handle_signup() if is_signup else self._handle_login()
            ),
            ft.TextButton(
                "Already have an account? Sign In" if is_signup else "Don't have an account? Sign Up",
                on_click=lambda _: self._draw_login(not is_signup)
            )
        ])
        
        login_card = ft.Container(
            content=ft.Column(controls, horizontal_alignment=ft.CrossAxisAlignment.CENTER, spacing=15, scroll=ft.ScrollMode.ADAPTIVE),
            padding=30,
            bgcolor="#111111",
            border_radius=20,
            width=card_width,
            border=ft.border.all(1, ft.Colors.WHITE_10)
        )
        
        self.viewport.controls.append(ft.Row([login_card], alignment=ft.MainAxisAlignment.CENTER))
        self.page.update()

    def _show_success(self, text):
        self.page.snack_bar = ft.SnackBar(
            content=ft.Row([
                ft.Icon(ft.Icons.CHECK_CIRCLE, color=ft.Colors.BLACK),
                ft.Text(text, color=ft.Colors.BLACK, weight="bold")
            ], spacing=10),
            bgcolor=ft.Colors.GREEN,
            behavior=ft.SnackBarBehavior.FLOATING,
            width=400, # Fixed width for the float
            duration=3000
        )
        self.page.snack_bar.open = True
        self.page.update()

    def _handle_signup(self):
        success, msg = self.api.signup(self.login_name.value, self.login_email.value, self.login_pass.value)
        if success:
            self._show_banner("Signup successful! Welcome to the loop.", ft.Colors.GREEN)
            self._draw_login(False)
        else:
            self._show_banner(f"Signup failed: {msg}", ft.Colors.RED_700)

    def _handle_login(self, email=None, password=None, is_auto=False):
        login_email = email or self.login_email.value
        login_pass = password or self.login_pass.value
        
        if not login_email or not login_pass:
            self._show_banner("Email and password are required", ft.Colors.RED_700)
            return

        success, msg = self.api.login(login_email, login_pass)
        if success: 
            if not is_auto:
                self._show_banner(f"Welcome back, {self.api.user.get('username')}!", ft.Colors.GREEN)
                # Persist credentials on successful manual login
                self.settings.set_auth_credentials(login_email, login_pass)
            
            # Preload libraries in background
            def _preload_libraries():
                try:
                    import time
                    self.cached_libraries = self.api.get_libraries()
                    self.library_last_updated = time.time()
                except Exception as e:
                    print(f"[Preload] Library preload failed (network issue): {e}")
            threading.Thread(target=_preload_libraries, daemon=True).start()
            self._show_home()
        else:
            if is_auto:
                print(f"[Auto-Login] Failed: {msg}")
                self._show_home() # Still show home (login screen will trigger)
            else:
                self._show_banner(f"Login failed: {msg}", ft.Colors.RED_700)

    def _handle_logout(self):
        self.api.user = None
        self.settings.clear_auth_credentials()
        self._show_banner("Logged out successfully", ft.Colors.BLUE_400)
        self._show_home()

    def _handle_search(self):
        q = self.search_bar.value
        if not q: return
        
        # Ensure we are in search view
        self.current_view = "search"
        
        # PERFORMANCE: Guard against rapid successive searches
        now = time.time()
        if hasattr(self, '_last_search_time') and now - self._last_search_time < 0.3:
            return  # Ignore rapid re-searches (300ms guard)
        self._last_search_time = now
        
        # PERFORMANCE: Cancel previous search if still running
        self._cancel_pending_operations()
        
        # Add to recent searches (keep last 5)
        if q not in self.recent_searches:
            self.recent_searches.insert(0, q)
            self.recent_searches = self.recent_searches[:5]
            self.settings.set_recent_searches(self.recent_searches)  # Persist immediately
        
        self.viewport.controls.clear()
        self.viewport.controls.append(ft.Text(f"Results for '{q}'", size=24, weight="bold"))
        self.viewport.controls.append(ft.Container(height=20))
        
        # Add Loading Indicator
        self.viewport.controls.append(
            ft.Row(
                [
                    ft.ProgressRing(color=ft.Colors.GREEN, width=30, height=30),
                    ft.Text("Searching...", size=16, color=ft.Colors.GREY_400)
                ], 
                alignment=ft.MainAxisAlignment.CENTER
            )
        )
        self.page.update()
        
        def _req():
            try:
                print(f"[Search] Requesting: {q}")
                rs = self.api.search(q, search_type="all") # "all" returns albums too
                print(f"[Search] API returned 200. Result keys: {list(rs.keys()) if rs else 'None'}")
                
                def _update_res():
                    if self.current_view != "search": 
                        print("[Search] View changed, discarding results.")
                        return
                    
                    try:
                        # Clear loading indicator (and everything else) to rebuild cleanly
                        self.viewport.controls.clear()
                        self.viewport.controls.append(ft.Text(f"Results for '{q}'", size=24, weight="bold"))
                        self.viewport.controls.append(ft.Container(height=20))
                        
                        if rs:
                            # Display Albums Section
                            if rs.get("albums"):
                                self.viewport.controls.append(ft.Text("Albums", size=20, weight="bold"))
                                self._display_albums(rs["albums"])
                                self.viewport.controls.append(ft.Container(height=20))
                        
                            # Display Tracks Section
                            if rs.get("tracks"):
                                print(f"[Search] Found {len(rs['tracks'])} tracks")
                                self.viewport.controls.append(ft.Text("Tracks", size=20, weight="bold"))
                                self._display_tracks(rs["tracks"])
                            
                            if not rs.get("albums") and not rs.get("tracks"):
                                 self.viewport.controls.append(ft.Text("No results found."))
                        else:
                            self.viewport.controls.append(ft.Text("No results found."))
                        self.page.update()
                    except Exception as ex:
                        print(f"UI Update error in search: {ex}")

                self.page.run_thread(_update_res)
            except Exception as e:
                print(f"Search request error: {e}")
                # Clear loading indicator even on error
                def _error_clear():
                    if self.current_view == "search":
                        self.viewport.controls.clear()
                        self.viewport.controls.append(ft.Text(f"Search error: {str(e)}", color=ft.Colors.RED_400))
                        self.page.update()
                self.page.run_thread(_error_clear)
        
        # PERFORMANCE: Use thread pool instead of creating new thread
        self._add_future(self.thread_pool.submit(_req))

    def _display_albums(self, albums):
        row = ft.Row(scroll=ft.ScrollMode.HIDDEN, spacing=20)
        for a in albums:
            # Create a Card
            img = ft.Container(width=150, height=150, bgcolor="#2A2A2A", border_radius=10)
            if a.get('cover'): self._load_art(a['cover'], img)
            
            card = ft.Container(
                content=ft.Column([
                    img,
                    ft.Text(a.get("title"), width=150, weight="bold", max_lines=1, overflow=ft.TextOverflow.ELLIPSIS),
                    ft.Text(a.get("artist"), width=150, size=12, color="#AAAAAA", max_lines=1)
                ], spacing=5),
                on_click=lambda _, alb=a: self._show_album_details(alb),
                padding=10,
                border_radius=10,
                data="album_card",
                on_hover=lambda e: (setattr(e.control, "bgcolor", "#222" if e.data == "true" else None), e.control.update() if e.control.page else None)
            )
            row.controls.append(card)
        
        self.viewport.controls.append(ft.Container(content=row, height=240))

    def _show_album_details(self, album):
        self.viewport.controls.clear()
        self.viewport.controls.append(ft.Text("Loading Album...", size=24))
        self.page.update()
        
        def _fetch_alb():
            details = self.api.get_album_details(album['id'])
            
            def _update_ui():
                self.viewport.controls.clear()
                if not details: 
                    self.viewport.controls.append(ft.Text("Failed to load album.", color="red"))
                    self.page.update()
                    return

                # Header
                cover_img = ft.Container(width=200, height=200, bgcolor="#2A2A2A", border_radius=15, shadow=ft.BoxShadow(blur_radius=20, color=ft.Colors.with_opacity(0.3, ft.Colors.BLACK)))
                if details.get('cover'): self._load_art(details['cover'], cover_img)
                
                header = ft.Row([
                    cover_img,
                    ft.Column([
                        ft.Text("ALBUM", size=12, weight="bold", color=ft.Colors.GREEN),
                        ft.Text(details.get('title'), size=40, weight="bold"),
                        ft.Text(details.get('artist'), size=18, weight="bold", color="#CCCCCC"),
                        ft.Row([
                            ft.Text(f"{details.get('trackCount', 0)} tracks"),
                            ft.Text("•"),
                            ft.Text(str(details.get('releaseDate', '')).split('-')[0])
                        ], spacing=10, run_spacing=10),
                        ft.ElevatedButton(
                            "Play Album", 
                            icon=ft.Icons.PLAY_ARROW, 
                            bgcolor=ft.Colors.GREEN, 
                            color=ft.Colors.BLACK,
                            on_click=lambda _: self._play_all_from_lib(details['id']) if False else self._play_album_tracks(details.get('tracks', []))
                        )
                    ], spacing=5, alignment=ft.MainAxisAlignment.END)
                ], spacing=30, alignment=ft.MainAxisAlignment.START, vertical_alignment=ft.CrossAxisAlignment.END)
                
                self.viewport.controls.append(header)
                self.viewport.controls.append(ft.Container(height=30))
                
                # Tracks
                if details.get('tracks'):
                    self._display_tracks(details['tracks'])
                else:
                     self.viewport.controls.append(ft.Text("No tracks found."))
                
                self.page.update()
            
            self.page.run_thread(_update_ui)
        
        threading.Thread(target=_fetch_alb, daemon=True).start()

    def _play_album_tracks(self, tracks):
        if tracks:
            self.queue = tracks
            self.current_track_index = 0
            self._play_track(tracks[0])
            self.page.snack_bar = ft.SnackBar(ft.Text("Playing album..."))
            self.page.snack_bar.open = True
            self.page.update()

    def _display_tracks(self, tracks):
        # Cache results for refresh on download complete
        self.last_search_results = tracks
        grid = ft.Column(spacing=15) # Increased spacing
        for i, t in enumerate(tracks):
            # Check if track is downloaded
            is_downloaded = self.download_manager.is_downloaded(t.get("id"))
            
            # Larger scale: 55x55
            track_img_core = ft.Container(width=55, height=55, bgcolor="#1A1A1A", border_radius=8)
            track_tick = ft.Icon(ft.Icons.CHECK_CIRCLE, color=ft.Colors.GREEN, size=16, visible=is_downloaded)
            
            track_img = ft.Stack([
                track_img_core,
                ft.Container(content=track_tick, bottom=-2, right=-2, bgcolor=ft.Colors.with_opacity(0.8, "#020202"), border_radius=8, padding=1)
            ], width=55, height=55)
            
            # Hi-Res Badge (Pill style outside image)
            is_hires = t.get("audioQuality", {}).get("isHiRes", False)
            hires_badge = ft.Container(
                content=ft.Text("HI-RES", size=9, color=ft.Colors.BLACK, weight="bold"),
                bgcolor=ft.Colors.GREEN,
                padding=ft.Padding(6, 2, 6, 2), # Fixed padding
                border_radius=4,
                visible=is_hires
            )

            # Collection menu
            is_fav_view = getattr(self, "current_view", "") == "favorites"
            like_text = "Unlike" if is_fav_view else "Like"
            like_click = self._unlike_track if is_fav_view else self._like_track
            
            # Check mobile view
            is_mobile = getattr(self, 'is_mobile_view', False)
            if hasattr(self, 'page') and self.page:
                 if self.page.width < 600: is_mobile = True

            items=[
                ft.PopupMenuItem(content=ft.Text("Add to Library"), on_click=lambda _, trk=t: self._add_to_lib_picker(trk)),
                ft.PopupMenuItem(content=ft.Text("Add to Queue"), on_click=lambda _, trk=t: self._add_to_queue(trk)),
                ft.PopupMenuItem(content=ft.Text(like_text), on_click=lambda _, trk=t: like_click(trk)),
            ]
            
            if is_mobile and not is_downloaded:
                 # Add Download to menu in mobile only if not already downloaded
                 items.append(ft.PopupMenuItem(content=ft.Text("Download"), on_click=lambda _, trk=t: self._trigger_download(trk)))
            
            # If we are in a library view, add "Remove from Library"
            if hasattr(self, 'current_view_lib_id') and self.current_view_lib_id:
                items.append(ft.PopupMenuItem(
                    content=ft.Text("Remove from Library", color=ft.Colors.RED_400),
                    on_click=lambda _, trk=t, lid=self.current_view_lib_id: self._remove_track_confirm(lid, trk)
                ))

            menu = ft.PopupMenuButton(
                icon=ft.Icons.MORE_VERT,
                items=items
            )

            # Mobile-aware buttons
            dl_btn = self._create_download_button(t)
            dl_btn.visible = not is_mobile
            
            queue_btn = ft.IconButton(ft.Icons.ADD, icon_color=ft.Colors.GREEN, on_click=lambda _, trk=t: self._add_to_queue(trk), tooltip="Add to Queue")
            queue_btn.visible = not is_mobile

            row = ft.Container(
                content=ft.Row([
                    track_img,
                    ft.Column([
                        ft.Row([
                            ft.Text(t.get("title"), weight="bold", size=16, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS, expand=True),
                            hires_badge
                        ], spacing=10),
                        ft.Text(t.get("artist"), size=14, color=self._get_secondary_color(), max_lines=1)
                    ], expand=True, spacing=4),
                    # Buttons
                    dl_btn,
                    ft.Row([
                        queue_btn,
                        ft.IconButton(ft.Icons.PLAY_ARROW_ROUNDED, icon_size=30, icon_color=ft.Colors.GREEN, on_click=lambda _, idx=i: self._play_track_from_list(tracks, idx)),
                        menu
                    ], spacing=0)
                ]),
                padding=12, border_radius=12,
                on_hover=lambda e: self._on_track_hover(e)  # OPTIMIZED: Use throttled method
            )
            grid.controls.append(row)
            if t.get("albumCover"): self._load_art(t["albumCover"], track_img_core)
        self.viewport.controls.append(grid)
        self.page.update()
    
    def _on_track_hover(self, e):
        """OPTIMIZED: Throttled hover handler for track rows"""
        now = time.time()
        if not hasattr(self, '_last_track_hover'):
            self._last_track_hover = 0
        
        # PERFORMANCE: Skip if hovering too frequently (100ms throttle)
        if now - self._last_track_hover < 0.1:
            return
        self._last_track_hover = now
        
        # Update background
        e.control.bgcolor = "#1A1A1A" if e.data == "true" else ft.Colors.TRANSPARENT
        
        # PERFORMANCE: Update only this control
        try:
            e.control.update()
        except:
            pass

    def _play_from_list(self, tracks, idx):
        self.queue = tracks
        self.current_track_index = idx
        self._play_track(tracks[idx])

    def _load_art(self, url, container):
        """OPTIMIZED: Use thread pool instead of creating unlimited threads"""
        if not url:
            return
            
        # PERFORMANCE: Check cache first
        if url in self.image_cache:
            try:
                container.content = ft.Image(src=url, fit=ft.BoxFit.COVER, border_radius=5)
                if container.page:
                    container.update()
                return
            except:
                pass
        
        def _task():
            # PERFORMANCE: Controlled thread pool execution
            try:
                def _sync():
                    try:
                        container.content = ft.Image(src=url, fit=ft.BoxFit.COVER, border_radius=5)
                        self.image_cache[url] = True  # Mark as cached
                        if container.page:
                            container.update()
                    except:
                        pass
                
                if hasattr(self, 'page') and self.page:
                    self.page.run_thread(_sync)
            except:
                pass
        
        # PERFORMANCE: Submit to image pool (max 5 concurrent) instead of creating tracked futures
        self._add_future(self.image_pool.submit(_task))
    
    def _play_track_from_list(self, tracks, index):
        """Play a single track - only add that track to queue"""
        try:
            print(f"[Play] Playing single track: {tracks[index].get('title') if index < len(tracks) else 'unknown'}")
            # Only add the clicked track to queue, not the entire list
            if index < len(tracks):
                self.queue = [tracks[index]]
                self.current_track_index = 0
                # Immediate visual feedback - show loading state
                # Immediate visual feedback - OPTIMISTIC UI update
                # Update with REAL track info immediately to prevent race conditions
                try:
                    self.track_title.value = tracks[index].get('title', 'Unknown Title')
                    self.track_artist.value = tracks[index].get('artist', 'Unknown Artist')
                    self.play_btn.icon = ft.Icons.PAUSE_CIRCLE_FILLED # Assume success
                    if self.track_title.page:
                        self.track_title.update()
                        self.track_artist.update()
                        self.play_btn.update()
                except: 
                    pass
                # Start playback immediately in background
                self._play_track(tracks[index])
        except Exception as e:
            print(f"Play track from list error: {e}")

    def _on_player_error(self):
        def _task():
            try:
                print(f"[Player] Error detected. Retry count: {self.current_retry_count}")
                if self.current_retry_count < 2: # Max 2 retries
                    self.current_retry_count += 1
                    time.sleep(1) # Wait before retry
                    
                    track = self.player.current_track
                    if track:
                        print(f"[Player] Retrying {track.get('title')}...")
                        self._show_banner(f"Stream error. Retrying... ({self.current_retry_count}/2)", ft.Colors.ORANGE)
                        self._play_track(track, is_retry=True)
                else:
                    self._show_banner("Playback failed. Stream unavailable.", ft.Colors.RED)
            except Exception as e:
                print(f"Retry error: {e}")
        self.page.run_thread(_task)

    def _play_track(self, track, is_retry=False):
        def _task():
            try:
                if not is_retry:
                    self.current_retry_count = 0
                    
                track_id = track.get("id")
                
                # Check if track is downloaded locally
                local_path = self.download_manager.get_local_path(track_id)
                
                if local_path:
                    # Play from local file
                    print(f"[Local Playback] Playing from: {local_path}")
                    url = local_path  # Player will handle local file path
                else:
                    # Stream from API
                    print(f"[Stream Playback] Streaming track {track_id}")
                    url = self.api.get_stream_url(track_id)
                    if not url:
                        self._show_banner("Failed to get stream URL. This track might be unavailable.", ft.Colors.RED_400)
                        return

                self.player.play_url(url, track)
                
                # Add to play history (keep last 5)
                if track not in self.play_history:
                    self.play_history.insert(0, track)
                    self.play_history = self.play_history[:5]
                    self.settings.set_play_history(self.play_history)  # Persist immediately
                
                def _sync():
                    try:
                        self.track_title.value = track.get("title")
                        self.track_artist.value = track.get("artist")
                        
                        # Set Audio Quality Info
                        q = track.get("audioQuality", {})
                        if q.get("isHiRes"):
                            self.audio_quality_info.value = f"{q.get('maximumBitDepth')}bit / {q.get('maximumSamplingRate')}kHz"
                            self.audio_quality_info.visible = True
                        else:
                            self.audio_quality_info.visible = False
                            
                        # Update playback icons to playing state
                        self._update_playback_ui(True)
                        
                        # Sync Mobile Player Info
                        self.mobile_track_title.value = track.get("title")
                        self.mobile_track_artist.value = track.get("artist")
                        
                        # Set download indicator
                        is_local = self.download_manager.is_downloaded(track.get("id"))
                        self.track_art_tick.visible = is_local
                        self.mobile_track_art_tick.visible = is_local
                        
                        # Load art for both
                        if track.get("image"):
                            self._load_art(track.get("image"), self.track_art_img)
                            self._load_art(track.get("image"), self.mobile_track_art_img)
                        
                        # Update all controls
                        self.track_title.update()
                        self.track_artist.update()
                        self.audio_quality_info.update()
                        self.mobile_track_title.update()
                        self.mobile_track_artist.update()
                        self.mobile_track_art.update() # stack update
                        self.track_art.update() # stack update
                    except Exception as e:
                        print(f"UI update error: {e}")
                        
                    # Fetch lyrics - use thread pool (MOVED OUTSIDE EXCEPT)
                    self.lyrics_data = []
                    self.current_lyric_idx = -1
                    self.fetching_lyrics = True
                    self._add_future(self.thread_pool.submit(self._fetch_lyrics, track))
                    
                    try:
                        self.page.update()
                    except Exception as e:
                        print(f"UI Sync error: {e}")
                
                self.page.run_thread(_sync)
            except Exception as e:
                self._show_banner(f"Playback Error: {str(e)}", ft.Colors.RED_400)
                print(f"Playback task error: {e}")
                
        # PERFORMANCE: Use thread pool instead of creating new thread
        self._add_future(self.thread_pool.submit(_task))

    def _parse_lrc(self, lrc_text):
        import re
        lyrics = []
        lines = lrc_text.split("\n")
        pattern = re.compile(r"\[(\d+):(\d+\.\d+)\](.*)")
        for line in lines:
            match = pattern.match(line)
            if match:
                m, s, text = match.groups()
                ms = (int(m) * 60 + float(s)) * 1000
                lyrics.append((ms, text.strip()))
        return sorted(lyrics, key=lambda x: x[0])

    def _fetch_lyrics(self, track):
        try:
            res = self.api.get_lyrics(track.get("artist"), track.get("title"))
            raw = res.get("lyrics") if res else None
            if raw:
                self.lyrics_data = self._parse_lrc(raw)
            else:
                self.lyrics_data = [(0, "Lyrics not available for this track.")]
        except Exception as e:
            print(f"Lyrics fetch error: {e}")
            self.lyrics_data = [(0, "Failed to load lyrics.")]
        finally:
            self.fetching_lyrics = False
             # If we are currently in lyrics view, we should update the UI
            if self.current_view == "lyrics":
                 self.page.run_thread(self._show_lyrics_view_update)

    def _show_lyrics_view(self):
        # Toggle behavior: if already showing lyrics, go back to home if stack empty, or pop
        if self.current_view == "lyrics":
            self._handle_back()
            self._update_player_bar_buttons()
            return
        
        # Push to stack
        if self.current_view != "lyrics":
             arg = self.current_view_lib_id if self.current_view == "library_detail" else None
             self.view_stack.append((self.current_view, arg))

        self.current_view = "lyrics"
        # Instant switch - clear and show immediately
        try:
            self.viewport.controls.clear()
            
            # Create scrollable list directly
            self.lyrics_scroll = ft.ListView(
                spacing=20,
                expand=True,
                padding=ft.Padding(0, 0, 0, 0)  # Remove all padding
            )
            
            if not self.lyrics_data or len(self.lyrics_data) == 0:
                msg = "Loading lyrics..." if getattr(self, "fetching_lyrics", False) else "No lyrics loaded yet. Play a track to see lyrics."
                self.lyrics_scroll.controls.append(
                    ft.Container(
                        content=ft.Text(msg, size=18, color=self._get_secondary_color(), text_align=ft.TextAlign.CENTER)
                    )
                )
            else:
                for i, (_, txt) in enumerate(self.lyrics_data):
                    self.lyrics_scroll.controls.append(
                        ft.Container(
                            content=ft.Text(txt, size=22, color=self._get_secondary_color(), text_align=ft.TextAlign.CENTER, width=float("inf")),
                            alignment=ft.Alignment(0, 0),
                            key=f"lyric_{i}",
                            on_click=lambda _, ts=self.lyrics_data[i][0]: self.player.seek(ts) # Click to seek feature
                        )
                    )
                     
            # Update active button states
            self._update_player_bar_buttons()
                
            self.viewport.controls.append(
                ft.Container(
                    expand=True,
                    padding=ft.Padding(0, -50, 0, 0),  # -50px to shift up
                    content=self.lyrics_scroll,
                    alignment=ft.Alignment(0, 0)
                )
            )
            self.page.update()
        except Exception as e:
            print(f"Show lyrics error: {e}")

    def _show_lyrics_view_update(self):
        """Update lyrics view without toggling - used by background fetch"""
        if self.current_view != "lyrics": return
        
        # Determine strict update need
        self.viewport.controls.clear()
        
        self.lyrics_scroll = ft.ListView(
            spacing=20,
            expand=True,
            padding=ft.Padding(0, 100, 0, 100)
        )
        
        if not self.lyrics_data or len(self.lyrics_data) == 0:
            msg = "Loading lyrics..." if getattr(self, "fetching_lyrics", False) else "No lyrics loaded yet. Play a track to see lyrics."
            self.lyrics_scroll.controls.append(
                ft.Container(
                    content=ft.Text(msg, size=18, color=self._get_secondary_color(), text_align=ft.TextAlign.CENTER)
                )
            )
        else:
            for i, (_, txt) in enumerate(self.lyrics_data):
                self.lyrics_scroll.controls.append(
                    ft.Container(
                        content=ft.Text(txt, size=22, color=self._get_secondary_color(), text_align=ft.TextAlign.CENTER, width=float("inf")),
                        alignment=ft.Alignment(0, 0),
                        key=f"lyric_{i}",
                        on_click=lambda _, ts=self.lyrics_data[i][0]: self.player.seek(ts)
                    )
                )
        
        self.viewport.controls.append(
            ft.Container(
                expand=True,
                padding=ft.Padding(0, 100, 0, 0),
                content=self.lyrics_scroll,
                alignment=ft.Alignment(0, 0)
            )
        )
        self.page.update()

    def _update_playback_ui(self, is_playing):
        """Standardized method to update all play/pause icons and SMTC status"""
        icon = ft.Icons.PAUSE_CIRCLE_FILLED if is_playing else ft.Icons.PLAY_CIRCLE_FILLED
        
        # Update Desktop btn
        if hasattr(self, 'play_btn'):
            self.play_btn.icon = icon
            if self.play_btn.page:
                try: self.play_btn.update()
                except: pass
                
        # Update Mobile btn
        if hasattr(self, 'mobile_play_btn'):
            self.mobile_play_btn.icon = icon
            if self.mobile_play_btn.page:
                try: self.mobile_play_btn.update()
                except: pass

        # Update Mini Mobile btn
        if hasattr(self, 'mini_play_btn'):
            self.mini_play_btn.icon = ft.Icons.PAUSE if is_playing else ft.Icons.PLAY_ARROW
            if self.mini_play_btn.page:
                try: self.mini_play_btn.update()
                except: pass
                
        # Update Windows SMTC
        if hasattr(self, 'windows_media'):
            try: self.windows_media.set_playback_status(is_playing)
            except: pass

    def _toggle_mobile_player(self):
        """Toggle between expanded and collapsed mobile player states"""
        self.player_expanded = not self.player_expanded
        
        if self.player_expanded:
            self.player_bar.height = 175
            self.player_bar.padding = ft.Padding(15, 5, 15, 30)
            self.mobile_seek_row.visible = True
            self.mobile_controls_row.visible = True
            self.minimise_controls.visible = True
            self.mobile_mini_controls.visible = False
            self.expand_btn.visible = False
        else:
            self.player_bar.height = 60
            self.player_bar.padding = ft.Padding(15, 5, 15, 5)
            self.mobile_seek_row.visible = False
            self.mobile_controls_row.visible = False
            self.minimise_controls.visible = False
            self.mobile_mini_controls.visible = True
            self.expand_btn.visible = True
            
        try:
            self.player_bar.update()
        except:
            self.page.update()

    def _toggle_playback(self):
        # Immediate UI feedback
        try:
            is_currently_playing = (self.play_btn.icon == ft.Icons.PAUSE_CIRCLE_FILLED)
            new_playing_state = not is_currently_playing
            
            # Update icons immediately
            self._update_playback_ui(new_playing_state)
            
            # Then toggle player in background
            def _toggle_task():
                try:
                     if self.player.is_playing:
                         self.player.pause()
                     else:
                         self.player.resume()
                except Exception as e:
                    print(f"Player toggle error: {e}")
            
            self.page.run_thread(_toggle_task)
        except Exception as e:
            print(f"Toggle playback error: {e}")
    
    def _load_next_page(self):
        """Load next page of tracks"""
        if self.current_lib_id and self.has_more_tracks and not self.is_loading_more:
            self.current_lib_page += 1
            self._load_library_page(self.current_lib_id, self.current_lib_page)
    
    def _on_seek(self, value):
        """Handle seek slider changes"""
        if self.player.is_playing or self.player.current_track:
            # Convert slider value (0-1000) to position (0.0-1.0)
            position = value / 1000.0
            self.player.set_position(position)

    def _toggle_shuffle(self):
        import random
        self.shuffle_enabled = not self.shuffle_enabled
        if self.shuffle_enabled:
            self.original_queue = list(self.queue)
            random.shuffle(self.queue)
            color = ft.Colors.GREEN
        else:
            if hasattr(self, 'original_queue') and self.original_queue:
                self.queue = list(self.original_queue)
            color = ft.Colors.WHITE_30 # Default inactive color
        
        # Update Desktop
        self.shuffle_btn.icon_color = color
        try: self.shuffle_btn.update()
        except: pass
        
        # Update Mobile
        if hasattr(self, 'mobile_shuffle_btn'):
            self.mobile_shuffle_btn.icon_color = color
            try: self.mobile_shuffle_btn.update()
            except: pass
            
        self._show_success(f"Shuffle {'Enabled' if self.shuffle_enabled else 'Disabled'}")

    def _toggle_loop(self):
        # Cycle through loop modes: off -> loop_all -> loop_one -> off
        if self.loop_mode == "off":
            self.loop_mode = "all"
            icon = ft.Icons.REPEAT
            color = ft.Colors.GREEN
        elif self.loop_mode == "all":
            self.loop_mode = "one"
            icon = ft.Icons.REPEAT_ONE
            color = ft.Colors.GREEN
        else:
            self.loop_mode = "off"
            icon = ft.Icons.REPEAT
            color = ft.Colors.WHITE_30
            
        # Update Desktop
        self.repeat_btn.icon = icon
        self.repeat_btn.icon_color = color
        try: self.repeat_btn.update()
        except: pass
        
        # Update Mobile
        if hasattr(self, 'mobile_repeat_btn'):
            self.mobile_repeat_btn.icon = icon
            self.mobile_repeat_btn.icon_color = color
            try: self.mobile_repeat_btn.update()
            except: pass
            
        mode_text = "Loop All" if self.loop_mode == "all" else "Loop One" if self.loop_mode == "one" else "Loop Off"
        self._show_success(f"Mode: {mode_text}")

    def _next_track(self):
        """Enhanced next track with shuffle and loop support"""
        import random
        
        # Loop one: replay current track
        if self.loop_mode == "loop_one" and 0 <= self.current_track_index < len(self.queue):
            self._play_track(self.queue[self.current_track_index])
            return
        
        # Remove current track from queue if shuffle is enabled
        if self.shuffle_enabled and 0 <= self.current_track_index < len(self.queue):
            self.queue.pop(self.current_track_index)
            # Adjust index after removal
            if self.current_track_index >= len(self.queue):
                self.current_track_index = max(0, len(self.queue) - 1)
            
            # If queue is empty and loop_all, restore from original
            if len(self.queue) == 0 and self.loop_mode == "loop_all" and self.original_queue:
                self.queue = list(self.original_queue)
                random.shuffle(self.queue)
                self.current_track_index = 0
        else:
            # Normal sequential playback
            if self.current_track_index < len(self.queue) - 1:
                self.current_track_index += 1
            elif self.loop_mode == "loop_all":
                # Loop back to start
                self.current_track_index = 0
            else:
                # End of queue, no loop
                return
        
        # Play next track
        if 0 <= self.current_track_index < len(self.queue):
            self.queue_cache_dirty = True  # Invalidate cache on track change
            self._play_track(self.queue[self.current_track_index])

    def _add_to_queue(self, track):
        try:
            self.queue.append(track)
            self.queue_cache_dirty = True  # Invalidate cache
            # Show toast notification
            self._show_banner(f"Added to play queue: {track.get('title')}", ft.Colors.BLUE_400)
        except Exception as e:
            print(f"Add to queue error: {e}")

    def _show_queue(self, force=False):
        # Toggle behavior: if already showing queue, go back to home
        if self.current_view == "queue" and not force:
            self._handle_back()
            self._update_player_bar_buttons()
            return
        
        # Push to stack
        if self.current_view != "queue":
             arg = self.current_view_lib_id if self.current_view == "library_detail" else None
             self.view_stack.append((self.current_view, arg))

        self.current_view = "queue"
        
        # Use cached view if available and not dirty
        if self.queue_view_cache and not self.queue_cache_dirty and not force:
            self.viewport.controls.clear()
            self.viewport.controls.extend(self.queue_view_cache)
            self._update_player_bar_buttons()
            self.page.update()
            return
        
        # Build view (will be cached)
        try:
            self.viewport.controls.clear()
            
            # Header
            header = ft.Row([
                ft.Text("Current Queue", size=32, weight="bold", expand=True),
                ft.TextButton("Clear Queue", on_click=lambda _: self._clear_queue())
            ])
            self.viewport.controls.append(header)
            
            if not self.queue:
                empty_msg = ft.Text("Queue is empty", color=self._get_secondary_color())
                self.viewport.controls.append(empty_msg)
                self.queue_view_cache = [header, empty_msg]
                self.queue_cache_dirty = False
                self.page.update()
            else:
                # Build track list with full track cards (same as library)
                grid = ft.Column(spacing=10, scroll=ft.ScrollMode.AUTO, expand=True)
                
                for i, t in enumerate(self.queue):
                    # Check if currently playing
                    is_current = (i == self.current_track_index)
                    
                    # Cover art
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
                    
                    # Menu items (without "Add to Queue" since already in queue)
                    items = [
                        ft.PopupMenuItem(content=ft.Text("Add to Library"), on_click=lambda _, trk=t: self._add_to_lib_picker(trk)),
                        ft.PopupMenuItem(content=ft.Text("Like"), on_click=lambda _, trk=t: self._like_track(trk)),
                    ]
                    
                    menu = ft.PopupMenuButton(
                        icon=ft.Icons.MORE_VERT,
                        items=items
                    )
                    
                    row = ft.Container(
                        content=ft.Row([
                            track_img,
                            ft.Column([
                                ft.Row([
                                    ft.Text(t.get("title"), weight="bold" if is_current else "normal", size=16, max_lines=1, overflow=ft.TextOverflow.ELLIPSIS, expand=True),
                                    hires_badge
                                ], spacing=10),
                                ft.Text(t.get("artist"), size=14, color=self._get_secondary_color(), max_lines=1)
                            ], expand=True, spacing=4),
                            # Download button or checkmark
                            self._create_download_button(t),
                            ft.Row([
                                # Remove button instead of Add button
                                ft.IconButton(
                                    ft.Icons.REMOVE, 
                                    icon_color=ft.Colors.RED_400, 
                                    on_click=lambda _, idx=i: self._remove_from_queue(idx), 
                                    tooltip="Remove from Queue"
                                ),
                                ft.IconButton(
                                    ft.Icons.PLAY_ARROW_ROUNDED, 
                                    icon_size=30, 
                                    icon_color=ft.Colors.GREEN, 
                                    on_click=lambda _, idx=i: self._play_from_queue(idx)
                                ),
                                menu
                            ], spacing=0)
                        ]),
                        padding=12,
                        border_radius=12,
                        bgcolor=ft.Colors.GREEN_900 if is_current else ft.Colors.TRANSPARENT,
                        on_hover=lambda e: self._on_track_hover(e)
                    )
                    grid.controls.append(row)
                    if t.get("albumCover"): 
                        self._load_art(t["albumCover"], track_img)
                
                self.viewport.controls.append(grid)
                
                # Cache the view
                self.queue_view_cache = [header, grid]
                self.queue_cache_dirty = False
                
                self._update_player_bar_buttons()
                self.page.update()
                
        except Exception as e:
            print(f"Show queue error: {e}")
    
    def _remove_from_queue(self, index):
        """Remove track from queue at specific index"""
        try:
            if 0 <= index < len(self.queue):
                removed_track = self.queue.pop(index)
                
                # Adjust current index if needed
                if index < self.current_track_index:
                    self.current_track_index -= 1
                elif index == self.current_track_index and self.queue:
                    # If we removed currently playing track, play next
                    self._play_track(self.queue[self.current_track_index])
                
                # Mark cache as dirty and rebuild queue view
                self.queue_cache_dirty = True
                if self.current_view == "queue":
                    # Rebuild queue view to reflect removal (force refresh without toggle)
                    self._show_queue(force=True)
                    
                self._show_banner(f"Removed: {removed_track.get('title', 'track')}", ft.Colors.ORANGE)
        except Exception as e:
            print(f"Remove from queue error: {e}")
    
    def _clear_queue(self):
        """Clear all tracks from queue"""
        self.queue = []
        self.current_track_index = -1
        self.queue_cache_dirty = True
        self._show_queue(force=True)
        self._show_banner("Queue cleared", ft.Colors.ORANGE)
    
    def _play_from_queue(self, index):
        """Play specific track from queue"""
        if 0 <= index < len(self.queue):
            self.current_track_index = index
            self._play_track(self.queue[index])
            # Rebuild to show new current track
            self.queue_cache_dirty = True
            self._show_queue(force=True)

    def _prev_track(self):
        if self.current_track_index > 0:
            self.current_track_index -= 1
            self._play_track(self.queue[self.current_track_index])

    def _show_library(self):
        self.view_stack.clear()
        self.current_view = "library"
        self.current_view_lib_id = None
        
        # Immediate UI update
        self.viewport.controls.clear()
        self.viewport.controls.append(ft.Text("Your Collections", size=32, weight="bold"))
        
        # Show cached libraries immediately if available
        if self.cached_libraries:
            self._display_library_grid(self.cached_libraries)
        else:
            self.viewport.controls.append(
                ft.Column([
                    ft.Text("Loading Library...", color=ft.Colors.GREY_400),
                    ft.ProgressBar(width=400, color=ft.Colors.GREEN)
                ], horizontal_alignment=ft.CrossAxisAlignment.CENTER)
            )
        self.page.update()
        
        # Fetch updates in background
        def _fetch_and_update():
            if not self.api.user:
                 self.page.snack_bar = ft.SnackBar(ft.Text("Please sign in to access your library"))
                 self.page.snack_bar.open = True
                 self.page.update()
                 return

            import time
            libs = self.api.get_libraries()
            current_time = time.time()
            
            # Check if there are changes
            if self.cached_libraries != libs:
                self.cached_libraries = libs
                self.library_last_updated = current_time
                # Update UI if still on library view
                if self.current_view == "library":
                    def _update():
                        self.viewport.controls.clear()
                        self.viewport.controls.append(ft.Text("Your Collections", size=32, weight="bold"))
                        self._display_library_grid(libs)
                        self.page.update()
                    self.page.run_thread(_update)
            # Remove loading indicator if no changes but cache was empty
            elif not self.cached_libraries and self.current_view == "library":
                 def _clear_loading():
                     if len(self.viewport.controls) > 1:
                         self.viewport.controls.pop(1)
                         self.viewport.controls.append(ft.Text("No collections found.", color=ft.Colors.GREY_500))
                         self.page.update()
                 self.page.run_thread(_clear_loading)
        
        self._add_future(self.thread_pool.submit(_fetch_and_update))
    
    def _display_library_grid(self, libs):
        """Display library grid from cached or fresh data"""
        grid = ft.Column(spacing=10)
        for lib in libs:
            lib_row = ft.Container(
                content=ft.Row([
                    ft.Text(lib.get("name"), size=18, weight="bold", expand=True),
                    ft.IconButton(
                        ft.Icons.EDIT_OUTLINED,
                        icon_size=18,
                        icon_color=ft.Colors.BLUE_400,
                        on_click=lambda _, l=lib: self._edit_library_dialog(l),
                        tooltip="Edit"
                    ),
                    ft.IconButton(
                        ft.Icons.DELETE_OUTLINE,
                        icon_size=18,
                        icon_color=ft.Colors.RED_400,
                        on_click=lambda _, l=lib: self._delete_library_confirm(l),
                        tooltip="Delete"
                    )
                ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
                padding=ft.Padding(20, 15, 20, 15),
                bgcolor=self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A",
                border_radius=12,
                on_click=lambda _, l=lib: self._safe_navigate(lambda: self._show_remote_lib(l))
            )
            grid.controls.append(lib_row)
        self.viewport.controls.append(grid)
    

    def _delete_library_confirm(self, lib):
        def _on_confirm(_):
            if self.api.delete_library(lib['id']):
                self.page.snack_bar = ft.SnackBar(ft.Text(f"Deleted library '{lib['name']}'"))
                self.page.snack_bar.open = True
                self.confirm_dlg.open = False
                self._show_library()
            else:
                self.page.snack_bar = ft.SnackBar(ft.Text("Failed to delete library"))
                self.page.snack_bar.open = True
            self.page.update()

        self.confirm_dlg = ft.AlertDialog(
            modal=True,
            title=ft.Text("Delete Library?"),
            content=ft.Text(f"Are you sure you want to delete '{lib['name']}'? This cannot be undone."),
            actions=[
                ft.TextButton("Cancel", on_click=lambda _: setattr(self.confirm_dlg, "open", False) or self.page.update()),
                ft.ElevatedButton("Delete", bgcolor=ft.Colors.RED_700, color=ft.Colors.WHITE, on_click=_on_confirm)
            ],
            bgcolor=ft.Colors.with_opacity(0.9, self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A")
        )
        self.page.overlay.append(self.confirm_dlg)
        self.confirm_dlg.open = True
        self.page.update()

    def _edit_library_dialog(self, lib):
        name_field = ft.TextField(
            value=lib.get("name"),
            hint_text="Library Name",
            border_radius=15,
            border_color=ft.Colors.OUTLINE,
            focused_border_color=ft.Colors.GREEN
        )
        
        def _on_save(_):
            new_name = name_field.value.strip()
            if new_name and new_name != lib.get("name"):
                if self.api.update_library(lib['id'], name=new_name):
                    self.page.snack_bar = ft.SnackBar(ft.Text(f"Library renamed to '{new_name}'"))
                    self.page.snack_bar.open = True
                    edit_dlg.open = False
                    self._show_library()  # Refresh library list
                else:
                    self.page.snack_bar = ft.SnackBar(ft.Text("Failed to update library"))
                    self.page.snack_bar.open = True
            else:
                edit_dlg.open = False
            self.page.update()
        
        edit_dlg = ft.AlertDialog(
            modal=True,
            title=ft.Row([
                ft.Icon(ft.Icons.EDIT, color=ft.Colors.GREEN),
                ft.Text("Edit Library", weight="bold")
            ]),
            content=ft.Container(
                content=name_field,
                padding=ft.Padding(0, 10, 0, 10)
            ),
            actions=[
                ft.TextButton("Cancel", on_click=lambda _: setattr(edit_dlg, "open", False) or self.page.update()),
                ft.ElevatedButton("Save", bgcolor=ft.Colors.GREEN, color=ft.Colors.BLACK, on_click=_on_save)
            ],
            bgcolor=ft.Colors.with_opacity(0.9, "#0A0A0A")
        )
        self.page.overlay.append(edit_dlg)
        edit_dlg.open = True
        self.page.update()

    def _show_remote_lib(self, lib):
        self.current_view = "library_detail"
        self.current_view_lib_id = lib.get("id")
        self.viewport.controls.clear()
        
        # Header with Play All button
        self.viewport.controls.append(ft.Row([
            ft.Column([
                ft.Text(lib.get("name"), size=32, weight="bold"),
                ft.Text(f"Library", color=ft.Colors.WHITE_30)
            ], expand=True),
            ft.IconButton(
                ft.Icons.PLAY_CIRCLE_FILL, 
                icon_color=ft.Colors.GREEN, 
                icon_size=50,
                on_click=lambda _: self._play_all_from_lib(lib.get("id")),
                tooltip="Play All"
            ),
            ft.IconButton(
                ft.Icons.EDIT_OUTLINED, 
                icon_color=ft.Colors.BLUE_400, 
                on_click=lambda _, l=lib: self._edit_library_dialog(l),
                tooltip="Edit Library"
            ),
            ft.IconButton(
                ft.Icons.DELETE_OUTLINE, 
                icon_color=ft.Colors.RED_400, 
                on_click=lambda _, l=lib: self._delete_library_confirm(l),
                tooltip="Delete Library"
            )
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN))
        
        # Load all tracks using existing stable method
        def _fetch():
            ts = self.api.get_library_tracks(lib.get("id"), page=1, limit=1000)  # Load up to 1000 tracks
            # Verify we are still on this library before updating UI
            if self.current_view_lib_id == lib.get("id"):
                self.current_lib_tracks = ts  # Cache for refresh
                def _sync(): 
                    if self.current_view_lib_id == lib.get("id"):
                        self._display_tracks(ts)
                self.page.run_thread(_sync)
        
        self._add_future(self.thread_pool.submit(_fetch))
        
    def _load_library_page(self, lib_id, page=1):
        if self.is_loading_more:
            return
        
        self.is_loading_more = True
        
        def _fetch():
            try:
                print(f"[Pagination] Loading page {page} for library {lib_id}")
                ts = self.api.get_library_tracks(lib_id, page=page, limit=50)
                
                def _sync():
                    if ts:
                        # Add tracks to the column
                        for track in ts:
                            self._add_track_to_view(track, ts)
                        
                        # Check if we got less than 50 - means no more pages
                        if len(ts) < 50:
                            self.has_more_tracks = False
                            print(f"[Pagination] No more tracks (got {len(ts)})")
                            # Remove Load More button if it exists
                            if len(self.tracks_column.controls) > 0 and hasattr(self.tracks_column.controls[-1], 'data') and self.tracks_column.controls[-1].data == 'load_more':
                                self.tracks_column.controls.pop()
                        else:
                            # Add or update Load More button
                            load_more_btn = ft.Container(
                                content=ft.ElevatedButton(
                                    "Load More Tracks",
                                    icon=ft.Icons.EXPAND_MORE,
                                    on_click=lambda _: self._load_next_page(),
                                    bgcolor=ft.Colors.GREEN,
                                    color=ft.Colors.BLACK
                                ),
                                alignment=ft.alignment.Alignment(0, 0),
                                padding=ft.Padding(0, 20, 0, 20),
                                data='load_more'
                            )
                            # Remove old Load More button if exists
                            if len(self.tracks_column.controls) > 0 and hasattr(self.tracks_column.controls[-1], 'data') and self.tracks_column.controls[-1].data == 'load_more':
                                self.tracks_column.controls[-1] = load_more_btn
                            else:
                                self.tracks_column.controls.append(load_more_btn)
                    else:
                        self.has_more_tracks = False
                        print("[Pagination] No tracks returned")
                    
                    self.is_loading_more = False
                    self.page.update()
                
                self.page.run_thread(_sync)
            except Exception as e:
                print(f"[Pagination] Error: {e}")
                self.is_loading_more = False
        
        threading.Thread(target=_fetch, daemon=True).start()
    
    def _add_track_to_view(self, t, tracks):
        """Add a single track to the tracks column"""
        i = len(self.tracks_column.controls) - 1 if self.has_more_tracks else len(self.tracks_column.controls)  # Account for Load More button
        
        # Build track UI (simplified version of _display_tracks logic)
        track_img = ft.Container(width=55, height=55, bgcolor="#1A1A1A", border_radius=8)
        
        is_hires = t.get("audioQuality", {}).get("isHiRes", False)
        hires_badge = ft.Container(
            content=ft.Text("HI-RES", size=9, color=ft.Colors.BLACK, weight="bold"),
            bgcolor=ft.Colors.GREEN,
            padding=ft.Padding(6, 2, 6, 2),
            border_radius=4,
            visible=is_hires
        )
        
        items = [
            ft.PopupMenuItem(content=ft.Text("Add to Library"), on_click=lambda _, trk=t: self._add_to_lib_picker(trk)),
            ft.PopupMenuItem(content=ft.Text("Add to Queue"), on_click=lambda _, trk=t: self._add_to_queue(trk)),
            ft.PopupMenuItem(content=ft.Text("Like"), on_click=lambda _, trk=t: self._like_track(trk)),
        ]
        
        if hasattr(self, 'current_view_lib_id') and self.current_view_lib_id:
            items.append(ft.PopupMenuItem(
                content=ft.Text("Remove from Library", color=ft.Colors.RED_400),
                on_click=lambda _, trk=t, lid=self.current_view_lib_id: self._remove_track_confirm(lid, trk)
            ))
        
        menu = ft.PopupMenuButton(items=items, icon=ft.Icons.MORE_VERT)
        
        track_row = ft.Container(
            content=ft.Row([
                track_img,
                ft.Column([
                    ft.Row([ft.Text(t.get("title"), size=16, weight="bold", max_lines=1, overflow=ft.TextOverflow.ELLIPSIS), hires_badge], spacing=8),
                    ft.Text(t.get("artist"), size=14, max_lines=1)
                ], expand=True, spacing=4),
                ft.Row([
                    ft.IconButton(ft.Icons.ADD, icon_color=ft.Colors.GREEN, on_click=lambda _, trk=t: self._add_to_queue(trk), tooltip="Add to Queue"),
                    ft.IconButton(ft.Icons.PLAY_ARROW_ROUNDED, icon_size=30, icon_color=ft.Colors.GREEN, on_click=lambda _: self._play_from_list(tracks, i)),
                    menu
                ], spacing=0)
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
            bgcolor=self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A",
            padding=ft.Padding(15, 12, 15, 12),
            border_radius=12,
            on_hover=lambda e: setattr(e.control, "bgcolor", "#121212" if e.data == "true" else "#0A0A0A") or e.control.update()
        )
        
        # Insert before the Load More button if it exists
        if self.has_more_tracks and len(self.tracks_column.controls) > 0:
            # Insert before last item (Load More button)
            self.tracks_column.controls.insert(-1, track_row)
        else:
            self.tracks_column.controls.append(track_row)
        
        # Load art asynchronously
        if t.get("albumCover"):
            self._load_art(t["albumCover"], track_img)

    def _play_all_from_lib(self, lib_id):
        ts = self.api.get_library_tracks(lib_id)
        if ts:
            self.queue = ts
            self.current_track_index = 0
            self._play_track(ts[0])
            self.page.snack_bar = ft.SnackBar(ft.Text("Playing library..."))
            self.page.snack_bar.open = True
            self.page.update()

    def _remove_track_confirm(self, lib_id, track):
        def _on_confirm(_):
            if self.api.remove_track_from_library(lib_id, track['id']):
                self.page.snack_bar = ft.SnackBar(ft.Text(f"Removed '{track['title']}' from library"))
                self.page.snack_bar.open = True
                self.rem_dlg.open = False
                # Refresh current view
                self._show_remote_lib({'id': lib_id, 'name': track.get('albumTitle', 'Library')})
            else:
                self.page.snack_bar = ft.SnackBar(ft.Text("Failed to remove track"))
                self.page.snack_bar.open = True
            self.page.update()

        self.rem_dlg = ft.AlertDialog(
            title=ft.Text("Remove track?"),
            actions=[
                ft.TextButton("Cancel", on_click=lambda _: setattr(self.rem_dlg, "open", False) or self.page.update()),
                ft.ElevatedButton("Remove", bgcolor=ft.Colors.RED_700, color=ft.Colors.WHITE, on_click=_on_confirm)
            ],
            bgcolor=ft.Colors.with_opacity(0.9, self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A")
        )
        self.page.overlay.append(self.rem_dlg)
        self.rem_dlg.open = True
        self.page.update()

    def _trigger_download(self, track):
        """Standalone method to trigger a track download"""
        tid = track.get("id")
        stream_url = self.api.get_stream_url(tid)
        if stream_url:
            # Progress callback
            def _on_progress(track_id, progress):
                self.download_manager.active_downloads[track_id] = progress
            
            # Completion callback
            def _on_complete(track_id, success, msg):
                self._on_download_complete(track_id, success, msg)
                # Trigger final refresh to show checkmark
                def _final_update():
                    import time
                    time.sleep(1)  # Wait for download manager to update
                    if self.current_view == "search" and self.last_search_results:
                        self.viewport.controls.clear()
                        self.viewport.controls.append(ft.Text("Search Results", size=24, weight="bold"))
                        self._display_tracks(self.last_search_results)
                        self.page.update()
                    elif self.current_view == "library" and self.current_lib_tracks:
                        if len(self.viewport.controls) > 1:
                            self.viewport.controls = self.viewport.controls[:1]
                        self._display_tracks(self.current_lib_tracks)
                        self.page.update()
                    elif self.current_view == "queue":
                        self._show_queue(force=True)
                    elif self.current_view == "home":
                        self._show_home()
                threading.Thread(target=_final_update, daemon=True).start()
            
            self.download_manager.download_track(
                str(tid), stream_url, track.get("title"), track.get("artist"),
                progress_callback=_on_progress,
                completion_callback=_on_complete
            )
            self._show_banner(f"Downloading: {track.get('title')}", ft.Colors.BLUE_400)

    def _create_download_button(self, track):
        """Create download button, progress indicator, or checkmark for a track"""
        track_id = str(track.get("id"))
        is_downloaded = self.download_manager.is_downloaded(track_id)
        is_downloading = self.download_manager.is_downloading(track_id)
        
        if is_downloaded:
            # Show checkmark for downloaded tracks
            return ft.IconButton(
                ft.Icons.CHECK_CIRCLE,
                icon_color=ft.Colors.GREEN,
                tooltip="Downloaded",
                icon_size=20
            )
        elif is_downloading:
            # Show circular progress indicator during download
            progress = self.download_manager.get_download_progress(track_id) or 0
            return ft.Container(
                content=ft.Stack([
                    ft.ProgressRing(
                        value=progress / 100,
                        width=20,
                        height=20,
                        stroke_width=2,
                        color=ft.Colors.BLUE_400
                    ),
                    ft.Container(
                        content=ft.Text(f"{int(progress)}", size=8, color=ft.Colors.WHITE),
                        alignment=ft.alignment.Alignment(0, 0),
                        width=20,
                        height=20
                    )
                ]),
                width=40,
                height=40,
                alignment=ft.alignment.Alignment(0, 0)
            )
        else:
            # Show download button
            return ft.IconButton(
                ft.Icons.DOWNLOAD,
                icon_color=ft.Colors.GREEN,  # Always green for visibility
                tooltip="Download",
                icon_size=20,
                on_click=lambda _: self._trigger_download(track)
            )
    
    
    def _start_download_refresh_timer(self):
        """Periodically refresh UI to show download progress"""
        def _refresh_loop():
            import time
            last_refresh = 0
            while self.running:
                time.sleep(2)  # Reduced from 0.5s to 2s to reduce load
                
                if self.download_manager.active_downloads:
                    current_time = time.time()
                    # Debounce: only refresh if 2 seconds have passed since last refresh
                    if current_time - last_refresh < 2:
                        continue
                    
                    last_refresh = current_time
                    print(f"[Download Refresh] Active downloads: {len(self.download_manager.active_downloads)}, View: {self.current_view}")
                    
                    def _update():
                        try:
                            if self.current_view == "search" and self.last_search_results:
                                print("[Download Refresh] Refreshing search view")
                                # Clear to prevent duplicates
                                self.viewport.controls.clear()
                                self.viewport.controls.append(ft.Text("Search Results", size=24, weight="bold"))
                                self._display_tracks(self.last_search_results)
                                self.page.update()
                            elif self.current_view == "library" and self.current_view_lib_id:
                                # Refresh library track view by rebuilding from cache
                                print(f"[Download Refresh] Refreshing library view: {self.current_view_lib_id}")
                                if self.current_lib_tracks:
                                    # Keep header, remove track list
                                    if len(self.viewport.controls) > 1:
                                        self.viewport.controls = self.viewport.controls[:1]
                                    self._display_tracks(self.current_lib_tracks)
                                    self.page.update()
                            elif self.current_view == "library" and self.cached_libraries:
                                # Refresh main library list
                                print("[Download Refresh] Refreshing library list")
                                self.viewport.controls.clear()
                                self.viewport.controls.append(ft.Text("Your Collections", size=32, weight="bold"))
                                self._display_library_grid(self.cached_libraries)
                                self.page.update()
                            elif self.current_view == "queue":
                                # Refresh queue view
                                print("[Download Refresh] Refreshing queue view")
                                self._show_queue(force=True)
                            elif self.current_view == "home":
                                # Refresh home view
                                print("[Download Refresh] Refreshing home view")
                                self._show_home()
                        except Exception as e:
                            print(f"[Download Refresh] Error: {e}")
                    
                    try:
                        self.page.run_thread(_update)
                    except Exception as e:
                        print(f"[Download Refresh] Thread error: {e}")
        
        threading.Thread(target=_refresh_loop, daemon=True).start()
        print("[Download Refresh] Timer started (2s interval)")
    
    def _update_theme_colors(self):
        """Update theme colors for light/dark mode"""
        if self.current_theme == "light":
            # Light mode - different shades for contrast
            self.page_bg = "#F8F9FA"
            self.sidebar_bg = "#F0F2F5"  # Slightly darker gray for sidebar
            self.viewport_bg = "#FFFFFF"  # Pure white for main area
            self.card_bg = "#F8F9FA"  # Light gray for cards
            self.page.theme_mode = ft.ThemeMode.LIGHT
        else:
            # Dark mode
            self.page_bg = "#020202"
            self.sidebar_bg = "#0A0A0A"
            self.viewport_bg = "#020202"
            self.card_bg = "#1A1A1A"  # Slightly lighter for cards
            self.page.theme_mode = ft.ThemeMode.DARK
        
        # Apply to page
        self.page.bgcolor = self.page_bg

    def _update_player_bar_theme(self):
        """Update player bar colors based on theme"""
        if not hasattr(self, 'player_bar'): return
        
        is_light = self.current_theme == "light"
        # Primary text/icon color
        text_col = ft.Colors.BLACK if is_light else ft.Colors.WHITE
        # Secondary text/icon color (muted)
        sec_col = ft.Colors.BLACK_54 if is_light else ft.Colors.WHITE_30
        
        # Update Player Bar Background - CRITICAL FIX
        if hasattr(self, 'card_bg'):
            self.player_bar.bgcolor = ft.Colors.with_opacity(0.95, self.card_bg)
            self.player_bar.update()  # Force update
        
    def _get_text_color(self):
        return ft.Colors.BLACK if self.current_theme == "light" else ft.Colors.WHITE
        
    def _get_secondary_color(self):
        # Default to WHITE_30 if theme is not yet set or is "dark"
        if not hasattr(self, 'current_theme') or self.current_theme == "dark":
             return ft.Colors.WHITE_30
        return ft.Colors.BLACK_54 if self.current_theme == "light" else ft.Colors.WHITE_30

    def _update_player_bar_buttons(self):
        """Update active state of lyrics/queue buttons"""
        if hasattr(self, 'btn_lyrics') and self.btn_lyrics.current:
            is_active = self.current_view == "lyrics"
            self.btn_lyrics.current.icon_color = ft.Colors.GREEN if is_active else self._get_secondary_color()
            self.btn_lyrics.current.update()
            
        if hasattr(self, 'btn_queue') and self.btn_queue.current:
            is_active = self.current_view == "queue"
            self.btn_queue.current.icon_color = ft.Colors.GREEN if is_active else self._get_secondary_color()
            self.btn_queue.current.update()
            
    def _update_all_player_controls_theme(self):
        """Update all player controls for theme change - comprehensive update"""
        is_light = self.current_theme == "light"
        text_col = self._get_text_color()
        sec_col = self._get_secondary_color()

        # Update Text Controls
        if hasattr(self, 'track_title'): 
            self.track_title.color = text_col
            self.track_title.update()
        if hasattr(self, 'track_artist'): 
            self.track_artist.color = sec_col
            self.track_artist.update()
        if hasattr(self, 'time_cur'): 
            self.time_cur.color = sec_col
            self.time_cur.update()
        if hasattr(self, 'time_end'): 
            self.time_end.color = sec_col
            self.time_end.update()
        
        # Update Slider
        if hasattr(self, 'seek_slider'):
            self.seek_slider.inactive_color = ft.Colors.BLACK12 if is_light else ft.Colors.WHITE_10
            self.seek_slider.update()
        
        # Update Buttons
        if hasattr(self, 'play_btn'): 
            self.play_btn.icon_color = text_col
            self.play_btn.update()
        if hasattr(self, 'shuffle_btn'): 
            shuffle_color = ft.Colors.GREEN if self.shuffle_enabled else sec_col
            self.shuffle_btn.icon_color = shuffle_color
            self.shuffle_btn.update()
        if hasattr(self, 'repeat_btn'):
            loop_color = ft.Colors.GREEN if self.loop_mode != "off" else sec_col
            self.repeat_btn.icon_color = loop_color
            self.repeat_btn.update()
        
        # Refs via assign_ref (need .current)
        if hasattr(self, 'btn_prev') and self.btn_prev.current:
            self.btn_prev.current.icon_color = text_col
            self.btn_prev.current.update()
        if hasattr(self, 'btn_next') and self.btn_next.current:
            self.btn_next.current.icon_color = text_col
            self.btn_next.current.update()
        if hasattr(self, 'btn_lyrics') and self.btn_lyrics.current:
            self.btn_lyrics.current.icon_color = sec_col
            self.btn_lyrics.current.update()
        if hasattr(self, 'btn_queue') and self.btn_queue.current:
            self.btn_queue.current.icon_color = sec_col
            self.btn_queue.current.update()
        if hasattr(self, 'btn_vol') and self.btn_vol.current:
            self.btn_vol.current.icon_color = sec_col
            self.btn_vol.current.update()
        
        # ========== MOBILE PLAYER BAR THEME UPDATES ==========
        # Mobile text controls
        if hasattr(self, 'mobile_track_title'):
            self.mobile_track_title.color = text_col
            self.mobile_track_title.update()
        if hasattr(self, 'mobile_track_artist'):
            self.mobile_track_artist.color = sec_col
            self.mobile_track_artist.update()
        if hasattr(self, 'mobile_time_cur'):
            self.mobile_time_cur.color = sec_col
            self.mobile_time_cur.update()
        if hasattr(self, 'mobile_time_end'):
            self.mobile_time_end.color = sec_col
            self.mobile_time_end.update()
        
        # Mobile seek slider
        if hasattr(self, 'mobile_seek'):
            self.mobile_seek.inactive_color = ft.Colors.BLACK12 if is_light else ft.Colors.WHITE_10
            self.mobile_seek.update()
        
        # Mobile icon buttons
        if hasattr(self, 'mobile_play_btn'):
            self.mobile_play_btn.icon_color = text_col
            self.mobile_play_btn.update()
        if hasattr(self, 'mobile_prev_btn'):
            self.mobile_prev_btn.icon_color = text_col
            self.mobile_prev_btn.update()
        if hasattr(self, 'mobile_shuffle_btn'):
            shuffle_color = ft.Colors.GREEN if self.shuffle_enabled else sec_col
            self.mobile_shuffle_btn.icon_color = shuffle_color
            self.mobile_shuffle_btn.update()
        if hasattr(self, 'mobile_repeat_btn'):
            loop_color = ft.Colors.GREEN if self.loop_mode != "off" else sec_col
            self.mobile_repeat_btn.icon_color = loop_color
            self.mobile_repeat_btn.update()
        if hasattr(self, 'mini_play_btn'):
            self.mini_play_btn.icon_color = text_col
            self.mini_play_btn.update()
        if hasattr(self, 'mini_next_btn'):
            self.mini_next_btn.icon_color = text_col
            self.mini_next_btn.update()
        
        # Minimise label
        if hasattr(self, 'minimise_controls'):
            for ctrl in self.minimise_controls.controls:
                if isinstance(ctrl, ft.Text):
                    ctrl.color = sec_col
                    ctrl.update()
        
        # Collapse/Expand buttons
        if hasattr(self, 'collapse_btn'):
            self.collapse_btn.icon_color = sec_col
            self.collapse_btn.update()
        if hasattr(self, 'expand_btn'):
            self.expand_btn.icon_color = sec_col
            self.expand_btn.update()

    def _show_banner(self, message, bgcolor=ft.Colors.GREEN, duration=3):
        """Show a notification banner at the top of the viewport"""
        def _display():
            try:
                # Create notification banner
                banner = ft.Container(
                    content=ft.Row([
                        ft.Icon(ft.Icons.CHECK_CIRCLE if bgcolor == ft.Colors.GREEN else ft.Icons.ERROR, color=ft.Colors.WHITE, size=20),
                        ft.Text(message, color=ft.Colors.WHITE, size=14, weight="bold"),
                    ], spacing=10),
                    bgcolor=bgcolor,
                    padding=15,
                    border_radius=10,
                    margin=ft.Margin(10, 10, 10, 0),
                    animate_opacity=300,
                )
                
                # Insert at top of viewport
                self.viewport.controls.insert(0, banner)
                self.page.update()
                
                # Auto-remove after duration
                import time
                import threading
                def _remove():
                    time.sleep(duration)
                    try:
                        if banner in self.viewport.controls:
                            self.viewport.controls.remove(banner)
                            self.page.update()
                    except:
                        pass
                
                threading.Thread(target=_remove, daemon=True).start()
                
            except Exception as e:
                print(f"Banner error: {e}")
        
        # Run in UI thread
        try:
            self.page.run_thread(_display)
        except:
            _display()
    
    def _on_download_complete(self, track_id, success, message):
        """Handle download completion"""
        if success:
            self._show_banner("Download complete!", ft.Colors.GREEN)
        else:
            self._show_banner(f"Download failed: {message}", ft.Colors.RED_700)
    
    def _show_settings(self):
        self.view_stack.clear()
        self.current_view = "settings"
        """Display settings panel in background thread to avoid freeze"""
        self.viewport.controls.clear()
        self.viewport.controls.append(ft.Text("Settings", size=32, weight="bold"))
        self.viewport.controls.append(ft.Container(height=20))
        self.viewport.controls.append(ft.ProgressBar(width=400, color=ft.Colors.GREEN))
        self.page.update()
        
        def _build_settings_ui():
            # Heavy lifting here (getting sizes, file counts etc)
            current_theme = self.settings.get_theme()
            current_location = self.settings.get_download_location()
            active_downloads = self.download_manager.active_downloads
            active_downloads_text = ""
            if active_downloads:
                active_downloads_text = f"Active Downloads: {len(active_downloads)}"
            
            downloaded_count = self.settings.get_downloaded_count()
            try:
                storage_size = self.settings.get_storage_size()
                storage_mb = storage_size / (1024 * 1024)
            except:
                storage_mb = 0

            # UI Construction callback to run on main thread
            def _update_ui():
                if self.current_view != "settings": return
                
                # Clear loading
                self.viewport.controls.pop() # Remove progress bar
                
                def _on_theme_change(e):
                    new_theme = "light" if e.control.value else "dark"
                    self.settings.set_theme(new_theme)
                    self.current_theme = new_theme
                    
                    # Update all theme colors
                    self._update_theme_colors()
                    
                    # Apply to page
                    self.page.theme_mode = ft.ThemeMode.LIGHT if new_theme == "light" else ft.ThemeMode.DARK
                    self.page.bgcolor = self.page_bg
                    
                    # Update sidebar
                    if hasattr(self, 'sidebar'):
                        self.sidebar.bgcolor = self.sidebar_bg
                    
                    # Update viewport container if it exists
                    if hasattr(self, 'viewport_container'):
                        self.viewport_container.bgcolor = self.viewport_bg
                    
                    self.page.update()
                    self._show_banner(f"Theme changed to {new_theme.title()}", ft.Colors.GREEN)
                    # Update main container bgcolor
                    self.main_container.bgcolor = self.viewport_bg
                    self.page.update()
                    
                    # Rebuild settings view to apply new theme colors
                    self._show_settings()
                    
                    # Update player bar theme
                    self._update_player_bar_theme()
                    self._update_all_player_controls_theme()
                    
                    # Update playback UI state
                    self._update_playback_ui(True)
                    
                    self.page.update()
                
                theme_switch = ft.Switch(
                    label="Light Mode",
                    value=current_theme == "light",
                    on_change=_on_theme_change
                )
                
                # Clear Cache Button
                def _clear_cache(e):
                    self.settings.clear_cache()
                    self.page.snack_bar = ft.SnackBar(ft.Text("Cache cleared successfully"))
                    self.page.snack_bar.open = True
                    self._show_settings()
                
                clear_btn = ft.FilledButton(
                    "Clear Downloaded Tracks",
                    icon=ft.Icons.DELETE_SWEEP,
                    on_click=_clear_cache,
                    style=ft.ButtonStyle(bgcolor=ft.Colors.RED_700, color=ft.Colors.WHITE, shape=ft.RoundedRectangleBorder(radius=10))
                )
                
                # Settings container
                settings_items = [
                    ft.Row([ft.Text("Theme", size=18, weight="bold"), theme_switch], spacing=20),
                    ft.Container(height=20),
                    ft.Text(f"Download Location: {current_location}", size=14),
                    ft.Container(height=20),
                ]
                
                # Add active downloads if any
                if active_downloads:
                    settings_items.append(ft.Text(active_downloads_text, size=14, color=ft.Colors.BLUE_400))
                    settings_items.append(ft.Container(height=10))
                
                settings_items.extend([
                    ft.Text(f"Downloaded Tracks: {downloaded_count} ({storage_mb:.2f} MB)", size=14),
                    ft.Container(height=10),
                    clear_btn
                ])
                
                settings_container = ft.Container(
                    content=ft.Column(settings_items, scroll=ft.ScrollMode.ADAPTIVE),
                    padding=20,
                    bgcolor=self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A",  # Dynamic theme color
                    border_radius=15,
                    expand=True,
                    width=600 # Use fixed width for settings card
                )
                
                self.viewport.controls.append(ft.Row([settings_container], alignment=ft.MainAxisAlignment.START))
                self.page.update()

            self.page.run_thread(_update_ui)
            
        threading.Thread(target=_build_settings_ui, daemon=True).start()
        

        

        

        

        

        
        # Settings container

        
        # Add active downloads if any

        


    def _show_favorites(self):
        self.view_stack.clear()
        self.current_view = "favorites"
        if not self.api.user:
            self._show_home()
            self._show_banner("Please sign in to access your Liked Songs", ft.Colors.RED_400)
            return
        
        self.current_view = "favorites"
        self.viewport.controls.clear()
        self.viewport.controls.append(ft.Text("Liked Songs", size=32, weight="bold"))
        self.page.update()
        
        def _fetch():
            ts = self.api.get_favorites()
            # Verify we are still in favorites view
            if self.current_view == "favorites":
                def _sync():
                    if self.current_view == "favorites":
                        self._display_tracks(ts)
                self.page.run_thread(_sync)
        
        self._add_future(self.thread_pool.submit(_fetch))

    def _open_import(self):
        self.yt_query = ft.TextField(
            hint_text="Enter YouTube Playlist URL...", 
            expand=True, 
            on_submit=lambda e: self._do_yt_search(),
            border_radius=15,
            border_color=ft.Colors.OUTLINE
        )
        self.yt_results = ft.Column(scroll=ft.ScrollMode.ADAPTIVE, height=400)
        self.selected_yt_items = {} 
        self.last_yt_results = []  # Initialize to prevent crashes
        
        self.import_dlg = ft.AlertDialog(
            title=ft.Row([ft.Icon(ft.Icons.PLAYLIST_PLAY, color=ft.Colors.GREEN), ft.Text("YouTube Playlist Sync")], spacing=10),
            content=ft.Container(
                width=600,
                content=ft.Column([
                    ft.Text("Import tracks from a YouTube playlist", size=14),
                    ft.Container(height=10),
                    ft.Row([
                        self.yt_query,
                        ft.IconButton(ft.Icons.SYNC, icon_color=ft.Colors.GREEN, on_click=lambda _: self._do_yt_search(), tooltip="Sync Playlist")
                    ]),
                    ft.Divider(),
                    self.yt_results
                ], tight=True)
            ),
            actions=[
                ft.ElevatedButton("Import Selected", bgcolor=ft.Colors.GREEN, color=ft.Colors.BLACK, on_click=lambda _: self._start_bulk_import()),
                ft.TextButton("Close", on_click=lambda _: self._close_import())
            ],
            bgcolor=ft.Colors.with_opacity(0.9, self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A")
        )
        self.page.overlay.append(self.import_dlg) 
        self.import_dlg.open = True
        self.page.update()

    def _open_create_lib(self):
        name_field = ft.TextField(label="Library Name", border_radius=15, border_color=ft.Colors.OUTLINE)
        def _save(_):
            if name_field.value:
                res = self.api.create_library(name_field.value)
                if res:
                    self.page.snack_bar = ft.SnackBar(ft.Text(f"Created library '{name_field.value}'"))
                    self.page.snack_bar.open = True
                    self.create_dlg.open = False
                    self._show_library()
                self.page.update()

        self.create_dlg = ft.AlertDialog(
            title=ft.Row([ft.Icon(ft.Icons.ADD_BOX, color=ft.Colors.GREEN), ft.Text("New Library")], spacing=10),
            content=ft.Container(content=name_field, width=400),
            actions=[ft.TextButton("Cancel", on_click=lambda _: setattr(self.create_dlg, "open", False) or self.page.update()),
                     ft.ElevatedButton("Create", on_click=_save, bgcolor=ft.Colors.GREEN, color=ft.Colors.BLACK)],
            bgcolor=ft.Colors.with_opacity(0.95, self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A")
        )
        self.page.overlay.append(self.create_dlg)
        self.create_dlg.open = True
        self.page.update()

    def _add_to_lib_picker(self, track):
        libs = self.api.get_libraries()
        if not libs:
            self.page.snack_bar = ft.SnackBar(ft.Text("No libraries found. Create one first!"))
            self.page.snack_bar.open = True
            self.page.update()
            return
            
        def _add(lib_id):
            if self.api.add_track_to_library(lib_id, track):
                self.page.snack_bar = ft.SnackBar(ft.Text(f"Added to library"))
            else:
                self.page.snack_bar = ft.SnackBar(ft.Text("Failed to add track"))
            self.page.snack_bar.open = True
            self.picker_dlg.open = False
            self.page.update()

        lib_list = ft.Column([
            ft.ListTile(
                title=ft.Text(l['name'], weight="bold"), 
                leading=ft.Icon(ft.Icons.LIBRARY_MUSIC, color=ft.Colors.GREEN),
                on_click=lambda _, lid=l['id']: _add(lid)
            ) for l in libs
        ], scroll=ft.ScrollMode.ADAPTIVE, height=300)

        self.picker_dlg = ft.AlertDialog(
            title=ft.Row([ft.Icon(ft.Icons.ADD, color=ft.Colors.GREEN), ft.Text("Add to Library")], spacing=10),
            content=ft.Container(content=lib_list, width=400),
            actions=[ft.TextButton("Cancel", on_click=lambda _: setattr(self.picker_dlg, "open", False) or self.page.update())],
            bgcolor=ft.Colors.with_opacity(0.95, self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A")
        )
        self.page.overlay.append(self.picker_dlg)
        self.picker_dlg.open = True
        self.page.update()

    def _like_track(self, track):
        def _task():
            success = self.api.add_favorite(track)
            if success:
                self._show_banner(f"Added to Liked Songs: {track.get('title')}")
            else:
                self._show_banner("Failed to add to favorites", ft.Colors.RED_400)
        self.thread_pool.submit(_task)

    def _unlike_track(self, track):
        def _task():
            success = self.api.remove_favorite(track.get("id"))
            if success:
                self._show_banner(f"Removed from Liked Songs: {track.get('title')}")
                if self.current_view == "favorites":
                    # Instant refresh
                    self.page.run_thread(self._show_favorites)
            else:
                self._show_banner("Failed to remove from favorites", ft.Colors.RED_400)
        self.thread_pool.submit(_task)

    def _close_import(self):
        self.import_dlg.open = False
        self.page.update()

    def _do_yt_search(self):
        q = self.yt_query.value
        if not q: 
            return
        
        # Validate that it's a YouTube playlist URL
        if not ('youtube.com' in q or 'music.youtube.com' in q):
            self._show_banner("Please enter a valid YouTube or YouTube Music URL", ft.Colors.RED_700)
            return
        
        if 'list=' not in q:
            self._show_banner("Please enter a playlist URL (must contain 'list=')", ft.Colors.RED_700)
            return
        
        self.yt_results.controls.clear()
        self.yt_results.controls.append(ft.Text("Loading playlist...", color=ft.Colors.GREEN))
        self.yt_results.controls.append(ft.ProgressBar(color=ft.Colors.GREEN))
        self.page.update()
        
        def _task():
            try:
                print(f"[YT Import] Searching for: {q}")
                results = self.yt_api.search_yt(q)
                print(f"[YT Import] Got {len(results) if results else 0} results")
                
                def _update_ui():
                    self.yt_results.controls.clear()
                    self.selected_yt_items = {item['video_id']: True for item in results} if results else {}  # Default to selected
                    
                    if not results:
                        self.yt_results.controls.append(ft.Text("No results found. Please check the URL or try a different search.", color=ft.Colors.RED_400))
                    else:
                        grid = ft.Column(spacing=10)
                        for item in results:
                            cb = ft.Checkbox(
                                value=True,  # Default checked
                                on_change=lambda e, vid=item['video_id']: self._toggle_yt_item(vid, e.control.value)
                            )
                            grid.controls.append(
                                ft.Container(
                                    content=ft.Row([
                                        cb,
                                        ft.Column([
                                            ft.Text(item['title'], weight="bold", size=14, max_lines=2, overflow=ft.TextOverflow.ELLIPSIS),
                                            ft.Text(item['channel'], size=12, color=ft.Colors.WHITE_30)
                                        ], expand=True),
                                    ]),
                                    bgcolor="#1A1A1A", padding=10, border_radius=10
                                )
                            )
                        self.last_yt_results = results # Cache results for import
                        self.yt_results.controls.append(grid)
                        self.yt_results.controls.append(ft.Text(f"Found {len(results)} tracks", color=ft.Colors.GREEN, size=12))
                    self.page.update()
                
                self.page.run_thread(_update_ui)
            except Exception as e:
                print(f"[YT Import] Error: {e}")
                import traceback
                traceback.print_exc()
                
                def _error_ui():
                    self.yt_results.controls.clear()
                    self.yt_results.controls.append(ft.Text(f"Error: {str(e)}", color=ft.Colors.RED_400))
                    self.yt_results.controls.append(ft.Text("Please check the API key and try again.", color=ft.Colors.WHITE_30, size=12))
                    self.page.update()
                
                self.page.run_thread(_error_ui)
        
        threading.Thread(target=_task, daemon=True).start()

    def _toggle_yt_item(self, video_id, val):
        self.selected_yt_items[video_id] = val

    def _start_bulk_import(self):
        # Validate that we have results to import
        if not hasattr(self, 'last_yt_results') or not self.last_yt_results:
            self._show_banner("No playlist loaded. Please enter a playlist URL and sync first.", ft.Colors.ORANGE)
            return
        
        selected = [item for item in self.last_yt_results if self.selected_yt_items.get(item['video_id'])]
        if not selected:
            self._show_banner("No items selected. Please select at least one track.", ft.Colors.ORANGE)
            return
        
        # Close import dialog and show library picker
        self.import_dlg.open = False
        self.page.update()
        
        # Show library picker for destination
        libs = self.api.get_libraries()
        if not libs:
            self.page.snack_bar = ft.SnackBar(ft.Text("No libraries found. Create one first!"))
            self.page.snack_bar.open = True
            self.page.update()
            return
        
        def _start_import(lib_id):
            self.lib_picker_dlg.open = False
            self.page.update()
            
            # Start the import process
            def _import_task():
                total = len(selected)
                imported = 0
                
                for i, item in enumerate(selected):
                    try:
                        print(f"[Import] ({i+1}/{total}) Searching DAB for: {item['title']}")
                        
                        # Search DAB API for this track
                        results = self.api.search(item['title'], limit=1)
                        if results and results.get('tracks'):
                            track = results['tracks'][0]
                            # Add to library
                            if self.api.add_track_to_library(lib_id, track):
                                imported += 1
                                print(f"[Import] ✓ Added: {track.get('title')}")
                            else:
                                print(f"[Import] ✗ Failed to add: {item['title']}")
                        else:
                            print(f"[Import] ✗ No match found for: {item['title']}")
                    except Exception as e:
                        print(f"[Import] Error processing {item['title']}: {e}")
                
                # Show completion message
                def _done():
                    self.page.snack_bar = ft.SnackBar(
                        ft.Text(f"Import complete! Added {imported}/{total} tracks to library."),
                        bgcolor=ft.Colors.GREEN if imported > 0 else ft.Colors.ORANGE
                    )
                    self.page.snack_bar.open = True
                    self.page.update()
                
                self.page.run_thread(_done)
            
            threading.Thread(target=_import_task, daemon=True).start()
        
        lib_list = ft.Column([
            ft.ListTile(
                title=ft.Text(l['name'], weight="bold"), 
                leading=ft.Icon(ft.Icons.LIBRARY_MUSIC, color=ft.Colors.GREEN),
                on_click=lambda _, lid=l['id']: _start_import(lid)
            ) for l in libs
        ], scroll=ft.ScrollMode.ADAPTIVE, height=300)
        
        self.lib_picker_dlg = ft.AlertDialog(
            modal=True,
            title=ft.Row([ft.Icon(ft.Icons.DOWNLOAD, color=ft.Colors.GREEN), ft.Text(f"Import {len(selected)} tracks to...")], spacing=10),
            content=ft.Container(content=lib_list, width=400),
            actions=[ft.TextButton("Cancel", on_click=lambda _: setattr(self.lib_picker_dlg, "open", False) or self.page.update())],
            bgcolor=ft.Colors.with_opacity(0.95, self.card_bg if hasattr(self, 'card_bg') else "#1A1A1A")
        )
        self.page.overlay.append(self.lib_picker_dlg)
        self.lib_picker_dlg.open = True
        self.page.update()

    def _process_bulk_import(self, items, lib_id):
        def _task():
            total = len(items)
            done = 0
            found = 0
            
            self.page.snack_bar = ft.SnackBar(ft.Text(f"Importing {total} tracks..."), duration=None)
            self.page.snack_bar.open = True
            self.page.update()

            for item in items:
                # Search on DAB
                query = re.sub(r'\(.*?\)|\[.*?\]', '', item['title']).strip() # Clean title a bit
                res = self.api.search(query, limit=1)
                if res and res.get("tracks"):
                    track = res["tracks"][0]
                    if self.api.add_track_to_library(lib_id, track):
                        found += 1
                done += 1
                # Optional: update snackbar with progress
            
            self.page.snack_bar.open = False
            self.page.snack_bar = ft.SnackBar(ft.Text(f"Import Complete: {found}/{total} tracks added!"))
            self.page.snack_bar.open = True
            self._show_library() # Refresh library view
            self.page.update()
            
        threading.Thread(target=_task, daemon=True).start()

    def _on_keyboard(self, e: ft.KeyboardEvent):
        """Handle keyboard shortcuts - ignore if typing in text field"""
        # PERFORMANCE: Check for manual focus flags first
        if getattr(self, "_search_focused", False):
            return

        # Fallback for other text fields (Import, Create Library dialogs)
        try:
            focused = self.page.focused_control
            if focused and (isinstance(focused, ft.TextField) or hasattr(focused, "value")):
                # Check if it has a focus property that is actually true
                if getattr(focused, "focused", False):
                    return
        except:
            pass
        
        if e.key == "Space" or e.key == " ":
            self._toggle_playback()
        elif e.key == "Arrow Right":
            self._next_track()
        elif e.key == "Arrow Left":
            self._prev_track()
        elif e.key == "Escape" or e.key == "Backspace":
            self._handle_back()

    def _handle_back(self, e=None):
        """Handle back navigation (Escape or Back Button)"""
        # 1. Close open Dialogs/Overlays
        # Check overlay for open dialogs
        if self.page.overlay:
            for control in reversed(self.page.overlay):
                if hasattr(control, "open") and control.open:
                    control.open = False
                    self.page.update()
                    return
        
        # Check deprecated page.dialog just in case, safely
        if hasattr(self.page, "dialog") and self.page.dialog and self.page.dialog.open:
            self.page.dialog.open = False
            self.page.update()
            return

        # 2. History Stack (Queue, Lyrics, etc.)
        if self.current_view in ["queue", "lyrics", "album_detail"]:
            if self.view_stack:
                last_view, last_arg = self.view_stack.pop()
                self._restore_view(last_view, last_arg)
                return
            else:
                self._show_home()
                return

        # 3. Hierarchical Navigation
        if self.current_view == "library_detail":
            self._show_library()
            return

        if self.current_view in ["search", "library", "settings", "favorites", "import", "create_library"]:
            self._show_home()
            return
            
        # 4. Home - Minimize or Exit?
        # On mobile, the OS handles exit if we don't handle it. 
        # But we can minimize.
        # self.page.window_minimize()
        pass

    def _restore_view(self, view_name, view_arg=None):
        """Restore a view from history stack"""
        if view_name == "home": self._show_home()
        elif view_name == "search": self._show_search()
        elif view_name == "library": self._show_library()
        elif view_name == "favorites": self._show_favorites()
        elif view_name == "settings": self._show_settings()
        elif view_name == "library_detail" and view_arg:
            # Need to find the library object by ID
            # This is a bit tricky, let's look it up from cache
            if self.cached_libraries:
                for lib in self.cached_libraries:
                    if lib.get("id") == view_arg:
                        self._show_remote_lib(lib)
                        break
                else:
                    self._show_library() # Fallback
            else:
                self._show_library() # Fallback
        else:
            self._show_home() # Fallback


def main(page: ft.Page):
    DabFletApp(page)

if __name__ == "__main__":
    ft.app(target=main, assets_dir="assets")
