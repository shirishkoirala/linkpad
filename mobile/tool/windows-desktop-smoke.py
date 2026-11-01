"""Verify an installed Windows GUI starts its bundled helper and exits cleanly."""
import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import socket
import subprocess
import time


def listening():
    try:
        with socket.create_connection(('127.0.0.1', 4747), timeout=0.3):
            return True
    except OSError:
        return False


def has_window(pid):
    user32 = ctypes.WinDLL('user32', use_last_error=True)
    callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user32.IsWindowVisible.argtypes = [wintypes.HWND]
    user32.EnumWindows.argtypes = [callback, wintypes.LPARAM]
    found = []
    @callback
    def visit(window, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(window, ctypes.byref(owner))
        title = ctypes.create_unicode_buffer(256)
        user32.GetWindowTextW(window, title, len(title))
        if owner.value == pid and title.value == 'Linkpad' and user32.IsWindowVisible(window):
            found.append(window)
        return True
    user32.EnumWindows(visit, 0)
    return bool(found)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    if listening():
        raise RuntimeError('Test port 4747 must be free before launch')
    app = subprocess.Popen([str(binary)])
    try:
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if app.poll() is not None:
                raise RuntimeError(f'GUI exited early: {app.returncode}')
            if listening() and has_window(app.pid):
                break
            time.sleep(0.25)
        else:
            raise RuntimeError('GUI window or bundled TCP listener did not become ready')
        result = subprocess.run([
            'powershell', '-NoProfile', '-Command',
            f'Get-CimInstance Win32_Process -Filter "ParentProcessId = {app.pid}" | Select-Object -ExpandProperty ExecutablePath | ConvertTo-Json'
        ], check=True, capture_output=True, text=True)
        paths = json.loads(result.stdout)
        if isinstance(paths, str):
            paths = [paths]
        expected = binary.parent / 'linkpad-server.exe'
        if str(expected).lower() not in [p.lower() for p in paths if p]:
            raise RuntimeError(f'Bundled helper was not a child of the GUI: {paths}')
        print('Installed GUI window is visible and its bundled server is listening.')
    finally:
        app.terminate()
        app.wait(timeout=10)
    deadline = time.monotonic() + 10
    while listening() and time.monotonic() < deadline:
        time.sleep(0.1)
    if listening():
        raise RuntimeError('Server survived GUI termination')
    print('GUI shutdown closed the bundled server.')


if __name__ == '__main__':
    main()
