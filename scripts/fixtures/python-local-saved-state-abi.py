"""Fresh-process public Saved observation of an independently retained Run.

The parent supplies only synthetic fixture reference/expected correspondence.
No prepare, lowering, dispatch, execution or replacement Run is allowed here.
This exercises source SDK/raw Wasm/SQLite, not installed normal packages.
"""
import asyncio
import hashlib
import json
from pathlib import Path
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk import AsyncClient
from actql_sdk._local_core import LocalCore, _NORMAL_HOST_OPERATION_FUEL
from actql_sdk._local_product import InstalledLocalHost, _ordinary_core_limits


async def main():
    if len(sys.argv) != 3:
        raise ValueError('Expected original module and bounded fixture correspondence')
    document = Path(sys.argv[2])
    with document.open('rb') as source:
        wire = source.read(65537)
    if len(wire) > 65536:
        raise ValueError('Saved fixture correspondence exceeds its bound')
    saved = json.loads(wire)
    raw = Path(sys.argv[1]).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    core = LocalCore(raw, digest=digest, transfer_capacity=12 * 1024 * 1024,
        slots=128, resources=_ordinary_core_limits(), fuel=_NORMAL_HOST_OPERATION_FUEL)
    host = client = None
    try:
        host = InstalledLocalHost(core, Path(saved['state']),
            now=lambda: 1_800_000_000_000, observed_at='2026-11-18T00:00:00.000Z', sdk_finite=True)
        client = await AsyncClient._connect_local(host)
        original_call = core._call

        def only_saved(family, name, *args):
            if family in ('program', 'run', 'compute', 'task'):
                raise AssertionError('Saved observation prepared or dispatched another Run')
            return original_call(family, name, *args)

        with patch.object(core, '_call', side_effect=only_saved):
            execution = await client.attach(saved['ref'])
            assert (await execution.status()).to_dict() == saved['expected']
    finally:
        if client is not None:
            await client.aclose()
        if host is not None:
            await host.aclose()
        elif not core.close():
            raise AssertionError('Fresh Saved Core close remains pending')
    assert core._closed
    print(json.dumps({'success': True, 'actualCases': 1, 'module_sha256': digest,
        'case': 'public_separate_process_saved_status_without_prepare_or_dispatch'}))


asyncio.run(main())
