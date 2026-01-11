# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

# Custom helper to find ffmpeg
import os
ffmpeg_files = []
if os.path.exists("ffmpeg.exe"):
    ffmpeg_files.append(("ffmpeg.exe", "."))
if os.path.exists("ffprobe.exe"):
    ffmpeg_files.append(("ffprobe.exe", "."))

a = Analysis(
    ['main_build.py'],
    pathex=[],
    binaries=ffmpeg_files,
    datas=[('assets', 'assets')],
    hiddenimports=[
        'winrt.windows.foundation',
        'winrt.windows.foundation.collections',
        'winrt.windows.media',
        'winrt.windows.media.playback',
        'winrt.windows.storage.streams'
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='BeatBoss',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    version='version_info.txt',
    icon='assets/icon.ico' if os.path.exists('assets/icon.ico') else None
)
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
