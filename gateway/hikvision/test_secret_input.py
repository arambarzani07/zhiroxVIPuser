import io
import types
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from setup import ask_secret


class MaskedInputTests(unittest.TestCase):
    def test_password_is_masked_and_backspace_removes_a_character(self):
        keys = iter(['a', 'b', '\b', 'C', '9', '\r'])
        console = types.SimpleNamespace(getwch=lambda: next(keys))
        output = io.StringIO()
        with patch('setup.os.name', 'nt'), patch.dict('sys.modules', {'msvcrt': console}), redirect_stdout(output):
            result = ask_secret('Password: ')
        self.assertEqual(result, 'aC9')
        self.assertNotIn(result, output.getvalue())
        self.assertEqual(output.getvalue(), 'Password: **\b \b**\n')

    def test_control_keys_do_not_become_part_of_the_password(self):
        keys = iter(['\xe0', 'K', 'x', '\r'])
        console = types.SimpleNamespace(getwch=lambda: next(keys))
        with patch('setup.os.name', 'nt'), patch.dict('sys.modules', {'msvcrt': console}), redirect_stdout(io.StringIO()):
            self.assertEqual(ask_secret('Password: '), 'x')


if __name__ == '__main__':
    unittest.main()
