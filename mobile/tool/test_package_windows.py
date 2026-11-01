"""Portable checks for the Windows installer payload and Inno configuration."""
import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('packager', Path(__file__).with_name('package_desktop.py'))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class WindowsPackageTest(unittest.TestCase):
    def test_per_user_installer_contains_helper_and_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle, output, runtime = root / 'bundle', root / 'output', root / 'crt'
            output.mkdir()
            runtime.mkdir()
            for name in ['Linkpad.exe', 'linkpad-server.exe', 'flutter_windows.dll', 'data/icudtl.dat', 'data/app.so']:
                p = bundle / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(b'fixture')
            for name in ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']:
                (runtime / name).write_bytes(b'CRT fixture')
            iscc = root / 'ISCC.exe'
            iscc.touch()
            args = SimpleNamespace(bundle=bundle, output=output, version='0.1.0', iscc=iscc)
            destination = output / 'Linkpad-0.1.0-windows-x86_64-setup.exe'
            def compile_installer(*command, **_):
                script = Path(command[1])
                text = script.read_text(encoding='utf-8-sig')
                self.assertIn('PrivilegesRequired=lowest', text)
                self.assertIn('DefaultDirName={localappdata}\\Programs\\Linkpad', text)
                self.assertIn('AppId=com.shirishkoirala.linkpad', text)
                payload = script.parent / 'app'
                self.assertTrue((payload / 'linkpad-server.exe').is_file())
                self.assertTrue((payload / 'vcruntime140_1.dll').is_file())
                destination.write_bytes(b'installer fixture')
            with patch.object(packager.sys, 'platform', 'win32'), patch.object(packager.platform, 'machine', return_value='AMD64'), patch.object(packager, 'windows_runtime', return_value=runtime), patch.object(packager, 'run', side_effect=compile_installer):
                packager.windows(args)
                self.assertTrue(destination.with_suffix('.exe.sha256').is_file())
                self.assertNotIn(b'\r', destination.with_suffix('.exe.sha256').read_bytes())
                (runtime / 'vcruntime140_1.dll').unlink()
                with self.assertRaisesRegex(ValueError, 'Missing Visual C'):
                    packager.windows(args)


if __name__ == '__main__':
    unittest.main()
