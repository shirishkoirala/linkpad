"""Launch the real GTK app under Xvfb and check its bundled child lifecycle."""
import os
from pathlib import Path
import socket
import subprocess
import time

binary = Path(os.environ.get('LINKPAD_DESKTOP_SMOKE_BINARY',
                            '/work/mobile/build/linux/x64/release/bundle/linkpad_controller'))
log_path = Path('/results/desktop-startup.log')

def listening():
    try:
        with socket.create_connection(('127.0.0.1', 4747), timeout=0.3):
            return True
    except OSError:
        return False

assert not listening(), 'Test port must be free before app launch'
with log_path.open('w') as log:
    app = subprocess.Popen([str(binary)], stdout=log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            assert app.poll() is None, f'Desktop app exited early: {app.returncode}'
            if listening():
                break
            time.sleep(0.25)
        else:
            raise AssertionError('Desktop app did not start its bundled server')
        # Verify it is the packaged helper, running as a child of this app.
        expected = str(binary.parent / 'lib/linkpad-server')
        children = []
        for process in Path('/proc').iterdir():
            if not process.name.isdigit():
                continue
            try:
                command = (process / 'cmdline').read_bytes().split(b'\0')
                status = (process / 'status').read_text()
                if command and command[0].decode() == expected and f'PPid:\t{app.pid}\n' in status:
                    children.append(int(process.name))
            except (OSError, UnicodeError):
                pass
        assert len(children) == 1, f'Expected one bundled helper, found {children}'
        assert Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')), 'linkpad/identity.pem').exists()
        time.sleep(3)
        assert app.poll() is None, 'App did not remain running'
        assert 'Unhandled Exception' not in log_path.read_text(), log_path.read_text()
        print('GTK app launched, bundled helper started, TCP listener active.')
    finally:
        app.terminate()
        try:
            app.wait(timeout=8)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
        deadline = time.monotonic() + 8
        while listening() and time.monotonic() < deadline:
            time.sleep(0.1)
        assert not listening(), 'Helper survived parent termination'
        print('Parent termination closed the helper and released the listener.')
