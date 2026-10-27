"""安装脚本的无特权测试，不安装服务、不改动网络。"""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def run_setup(self, *args, **variables):
        env = {k: v for k, v in os.environ.items() if not k.startswith('MICROFLOW_')}
        env['MICROFLOW_BIG_CORES'] = ''
        env.update(variables)
        return subprocess.run(['bash', str(ROOT / 'setup.sh'), *args], env=env,
                              text=True, capture_output=True)

    def test_default_unit(self):
        r = self.run_setup('print-unit')
        self.assertEqual(r.returncode, 0, r.stderr)
        for item in ['User=', ' 18080 4', 'Restart=on-failure', 'ProtectHome=read-only',
                     'WantedBy=multi-user.target', 'MICROFLOW_HTTP_PORT=18080']:
            self.assertIn(item, r.stdout)
        self.assertNotIn('tailscale', r.stdout)
        self.assertIn(f'WorkingDirectory={ROOT}\n', r.stdout)

    def test_custom_port_threads(self):
        r = self.run_setup('print-unit', MICROFLOW_PORT='18081', MICROFLOW_THREADS='2')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(' 18081 2', r.stdout)
        self.assertIn('OMP_NUM_THREADS=2', r.stdout)

    def test_path_escape(self):
        r = self.run_setup('print-unit', MICROFLOW_MODEL='/tmp/a space/"100%.mflow')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(r'"/tmp/a space/\"100%%.mflow"', r.stdout)

    def test_bad_numbers(self):
        for value in ['0', '-1', 'abc', '65536', '08080', '80']:
            with self.subTest(value=value):
                self.assertNotEqual(self.run_setup('print-unit', MICROFLOW_PORT=value).returncode, 0)

    def test_bad_cpu(self):
        self.assertNotEqual(self.run_setup('print-unit', MICROFLOW_BIG_CORES='4;reboot').returncode, 0)

    def test_newline_path(self):
        self.assertNotEqual(self.run_setup('print-unit', MICROFLOW_MODEL='/tmp/a\nExecStart=no').returncode, 0)

    def test_usage(self):
        self.assertEqual(self.run_setup('help').returncode, 0)
        self.assertEqual(self.run_setup('unknown').returncode, 2)
        self.assertEqual(self.run_setup('print-unit', '--unknown').returncode, 2)


if __name__ == '__main__':
    unittest.main()
