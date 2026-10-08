"""Test-only noncooperative writer after staging and before publication."""
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from process_worker import serve


def factory(*args):
    from catalog import TableCatalog
    class Stalled(TableCatalog):
        def before_publication(self):
            Path(self.database).parent.joinpath("staged").write_text("staged", encoding="utf-8")
            while True:
                time.sleep(0.1)
    return Stalled(*args)


with os.fdopen(3, "r+b", buffering=0) as channel:
    serve(channel, factory)
