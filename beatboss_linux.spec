# -*- mode: python ; coding: utf-8 -*-
# BeatBoss Linux Spec - For AppImage/Debian packaging
from PyInstaller.utils.hooks import collect_data_files
import os

# Collect Flet data files
flet_datas = collect_data_files('flet')
flet_audio_datas = collect_data_files('flet_audio')

a = Analysis(
    ['src/main.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('src/assets', 'assets'),
    ] + flet_datas + flet_audio_datas,
    hiddenimports=[
        'flet_audio',
        'flet',
        'requests',
        'urllib3',
        'googleapiclient',
        'googleapiclient.discovery',
        'pynput',
        'pynput.keyboard',
        'colorama',
        'dotenv',
        'msgpack',
        # Removed 'winrt' for Linux
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

# One-Directory Mode (best for packaging)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='BeatBoss',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True, # Compress if possible
    console=False, # GUI app
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    # icon='src/assets/icon.png', # Optional: Linux desktops use .desktop files for icons
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='BeatBoss',
)
