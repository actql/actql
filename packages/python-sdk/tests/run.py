"""Focused runner: zero discovery and skipped-only suites are never success."""
from pathlib import Path
import sys
import unittest

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'src'))
suite = unittest.defaultTestLoader.discover(str(root / 'tests'), pattern='test_*.py')
result = unittest.TextTestRunner(verbosity=2).run(suite)
executed = result.testsRun - len(result.skipped)
print(f'Python client tests: executed={executed}, skipped={len(result.skipped)}', flush=True)
sys.exit(0 if executed > 0 and result.wasSuccessful() else 1)
