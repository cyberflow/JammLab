"""Run in the locked helper venv; no ML models or network are needed."""
import tempfile
import unittest
from pathlib import Path

import numpy as np
import soundfile as sf

from smoke_separator_helper import validate_outputs


class SmokeOutputTests(unittest.TestCase):
    def test_valid_stems(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for stem in ("vocals", "instrumental"):
                sf.write(path / f"fixture_({stem}).wav", np.ones(1000), 100, subtype="FLOAT")
            self.assertEqual(len(validate_outputs(path, {"vocals", "instrumental"})), 2)

    def test_rejects_missing_wrong_empty_nonfinite_and_wrong_duration(self):
        cases = [
            (None, None, "Expected"),
            ("wrong", np.ones(1000), "Missing stem"),
            ("vocals", np.zeros(0), "Empty or non-finite"),
            ("vocals", np.full(1000, np.nan), "Empty or non-finite"),
            ("vocals", np.ones(980), "Wrong stem duration"),
        ]
        for name, audio, message in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as directory:
                path = Path(directory)
                if name is not None:
                    sf.write(path / f"fixture_({name}).wav", audio, 100, subtype="FLOAT")
                with self.assertRaisesRegex(ValueError, message):
                    validate_outputs(path, {"vocals"})


if __name__ == "__main__":
    unittest.main()
