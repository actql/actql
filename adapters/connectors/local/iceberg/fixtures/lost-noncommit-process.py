"""Test-only process loss after original noncommit/fence persistence."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from process_worker import serve


def factory(*args):
    from catalog import TableCatalog
    class LostNoncommit(TableCatalog):
        def confirm_noncommit(self, request, reason):
            result = super().confirm_noncommit(request, reason)
            if result["version"] == "actql-table-noncommit-receipt/0.1":
                os._exit(9)
            return result
    return LostNoncommit(*args)


with os.fdopen(3, "r+b", buffering=0) as channel:
    serve(channel, factory)
