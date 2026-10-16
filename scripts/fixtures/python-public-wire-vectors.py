"""Consume independent common vectors with the installed Remote codec, without engines."""
import importlib.abc
import json
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root / 'packages/python-sdk/src'))


class RemoteOnly(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path=None, target=None):
        if fullname.split('.')[0] in {'wasmtime', 'duckdb', 'actql_local_runtime'}:
            raise AssertionError(fullname)


sys.meta_path.insert(0, RemoteOnly())
from actql_sdk import _wire as wire
from actql_sdk._values import decode_json
from actql_sdk import ClientError

vectors=json.load(sys.stdin)
assert len(vectors) > 0
results=[]
for entry in vectors:
    try:
        value=decode_json(entry['valueJSON'].encode('utf-8'))
        operation=entry['operation']
        if operation in ('profile', 'admission'):
            actual=wire.negotiated(value, operation, entry['selected'])
        elif operation == 'run_ref':
            actual=wire.valid(value, 'run_ref')
        elif operation in ('lookup','held'):
            actual=wire.correlated(value, 'request_lookup' if operation=='lookup' else 'held', entry['requestId'])
        elif operation=='cancellation':
            actual=wire.cancellation(value,json.loads(entry['expectedJSON']))
        elif operation=='check_outcome':
            actual=wire.check_outcome(value)
        else:
            raise AssertionError(operation)
    except ClientError:
        actual=False
    except Exception as error:
        results.append({'name':entry['name'],'error':type(error).__name__})
        continue
    results.append({'name':entry['name'],'actual':actual})
print(json.dumps(results))
