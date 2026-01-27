# -*- mode: python ; coding: utf-8 -*-
# BeatBoss - One-Directory Mode (faster startup)
from PyInstaller.utils.hooks import collect_data_files

# Collect Flet data files (icons.json, fonts, etc.)
flet_datas = collect_data_files('flet')
flet_audio_datas = collect_data_files('flet_audio')

a = Analysis(
    ['src\\main.py'],
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
        'winrt',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

# ONE-DIRECTORY: exclude_binaries=True means binaries go to COLLECT, not EXE
exe = EXE(
    pyz,
    a.scripts,
    [],                      # Empty - binaries go to COLLECT
    exclude_binaries=True,   # THIS IS THE KEY for one-dir mode
    name='BeatBoss',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,               # Disable UPX for faster startup
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='src\\assets\\icon.ico',
)

# COLLECT creates the output directory with all files pre-extracted
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name='BeatBoss',
)
