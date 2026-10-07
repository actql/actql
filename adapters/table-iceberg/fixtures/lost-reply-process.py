"""Test-only process loss after the real head/receipt transaction commits."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from process_worker import serve


def factory(*args):
    from catalog import TableCatalog
    class LostReply(TableCatalog):
        def after_publication(self):
            os._exit(9)
    return LostReply(*args)


with os.fdopen(3, "r+b", buffering=0) as channel:
    serve(channel, factory)
