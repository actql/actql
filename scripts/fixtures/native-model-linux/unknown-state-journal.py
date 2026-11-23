import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys
import tempfile

origin = Path(sys.argv[1]).resolve(strict=True)
definition = sys.argv[2]
request = sys.argv[3]
assert re.fullmatch(r'sha256:[0-9a-f]{64}', request)
assert re.fullmatch(r'sha256:[0-9a-f]{64}', definition)
assert origin.name == 'client.sqlite3'

def original_bytes(path):
    identity = path.lstat()
    body = path.read_bytes()
    assert identity.st_size == len(body) <= 16 * 1024 * 1024
    current = path.lstat()
    assert (identity.st_dev,identity.st_ino,identity.st_size,identity.st_mtime_ns,identity.st_ctime_ns) == (
        current.st_dev,current.st_ino,current.st_size,current.st_mtime_ns,current.st_ctime_ns)
    return (identity, hashlib.sha256(body).hexdigest(), body)

wal = origin.with_name(origin.name + '-wal')
originals = {origin: original_bytes(origin)}
if wal.exists():
    originals[wal] = original_bytes(wal)

# Recover the original WAL only in a private disposable copy. The CLI child
# has ended and the source generations below must still match.
with tempfile.TemporaryDirectory(prefix='private-journal-observation-',
                                 dir=Path(__file__).resolve().parent) as scratch:
    directory = Path(scratch)
    for original, (_, _, body) in originals.items():
        with (directory / original.name).open('xb') as output:
            output.write(body)
    with sqlite3.connect(directory / origin.name) as db:
        db.execute('pragma query_only=on')
        def rows(namespace):
            return [value for body, in db.execute(
                'select body from actql_records where namespace=?',(namespace,))
                if (value := json.loads(body)).get('run_definition_cid') == definition]
        entries = rows('client_model_call_originals')
        settlements = rows('client_model_call_settlements')
        (run,) = [json.loads(json.loads(body)['run_definition']) for body, in db.execute(
            'select body from actql_records where namespace=?', ('client_runs',))
            if json.loads(json.loads(body)['run_definition'])['run_definition_cid'] == definition]
        (submitted,) = [json.loads(body) for body, in db.execute(
            'select body from actql_records where namespace=?', ('client_submitted_intents',))
            if request.encode() in body and definition.encode() in body]
        state_wire = submitted.get('run_state_original')
        saved_status = None
        if state_wire is not None:
            observed_state = json.loads(state_wire)
            assert observed_state['run_definition_cid'] == definition
            saved_status = json.loads(observed_state['state'])['status']
        observed = {'entries':len(entries),'attempts':[json.loads(value['attempt'])['attempt']
             for value in entries],'settlements':len(settlements),'runId':run['run_id'],
             'savedStatus':saved_status,'observationRevision':int(submitted['run_state_revision'])}
for original, (identity, digest, _) in originals.items():
    current = original.lstat()
    assert (identity.st_dev,identity.st_ino,identity.st_size,identity.st_mtime_ns,identity.st_ctime_ns) == (
        current.st_dev,current.st_ino,current.st_size,current.st_mtime_ns,current.st_ctime_ns)
    assert hashlib.sha256(original.read_bytes()).hexdigest() == digest
assert wal.exists() == (wal in originals)
print(json.dumps(observed))
