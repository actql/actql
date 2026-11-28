"""Independent read-only checks for the ordinary controlled Python Model fixture."""

from base64 import b64decode, b64encode
from contextlib import closing
from hashlib import sha256
from pathlib import Path
import json
import re
import sqlite3
import stat


_ENTRY = 'client_model_call_originals'
_SETTLEMENT = 'client_model_call_settlements'
_RAW = 'client_model_raw_responses'
_EVIDENCE = 'client_model_evidence'
_ROLES = {
    'model_call_attempt', 'model_attempt_accounting', 'model_attempt_outcome',
    'model_dispatch_authority', 'model_slot_capture', 'model_invocation_evidence',
    'model_capture_bundle',
}
# This fixture contains one short non-media response and bounded metadata.
_MAX_FIXTURE_RECORD_BYTES = 65_536
# Current ordinary client_infer_host standard_limits. The retained Check can
# lower the request ceiling. HTTP Response Profile limits are separate.
_MODEL_STANDARD_REQUEST_BYTES = 65_536
_MODEL_STANDARD_RESPONSE_BYTES = 65_536
_MODEL_STANDARD_WORK = 10_000


def _canonical(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True,
                      separators=(',', ':')).encode('utf-8')


def _cid(raw):
    return 'sha256:' + sha256(raw).hexdigest()


def _require_cid(value):
    if type(value) is not str or re.fullmatch(r'sha256:[0-9a-f]{64}', value) is None:
        raise ValueError('Invalid original Model evidence identity')
    return value


def _unique_object(pairs):
    value = dict(pairs)
    if len(value) != len(pairs):
        raise ValueError('Repeated original Model evidence field')
    return value


def _object(wire):
    value = json.loads(wire, object_pairs_hook=_unique_object)
    if type(value) is not dict:
        raise ValueError('Invalid original Model evidence object')
    return value


def _sealed_identity(value):
    original = dict(value)
    identity = _require_cid(original.pop('self_cid', None))
    if _cid(_canonical(original)) != identity:
        raise ValueError('Changed original Model evidence identity')
    return identity


def _record_wire(key, generation, payload, prefix, require_generation):
    identity = _require_cid(key.removeprefix(prefix))
    if ((require_generation is not None and generation != require_generation)
            or not isinstance(payload, bytes)):
        raise ValueError('Unavailable or changed original Model Store record')
    return identity, generation, payload


def _record_rows(database, namespace, count, *, require_generation=0):
    prefix = f'namespace:{len(namespace)}:{namespace}:'
    rows = database.execute("""
        SELECT key, generation,
               CASE WHEN typeof(payload)='blob' AND length(payload) BETWEEN 1 AND ?
                    THEN payload END
        FROM core_bytes WHERE key >= ? AND key < ? ORDER BY key LIMIT ?
    """, (_MAX_FIXTURE_RECORD_BYTES, prefix, prefix[:-1] + ';', count + 1)).fetchall()
    if len(rows) != count:
        raise ValueError('Unexpected original Model Store inventory for ' + namespace)
    return [_record_wire(key, generation, payload, prefix, require_generation)
            for key, generation, payload in rows]


def _records(database, namespace, count):
    return {identity: body for identity, _, body in _record_rows(database, namespace, count)}


def _sealed_envelope(raw):
    value = _object(raw)
    if (set(value) != {'version', 'nonce', 'tag', 'ciphertext'}
            or value['version'] != 'actql-private-publication-evidence/0.1'):
        raise ValueError('Unexpected original Model ciphertext envelope')
    for field, extent in (('nonce', 12), ('tag', 16), ('ciphertext', None)):
        encoded = value[field]
        if type(encoded) is not str:
            raise ValueError('Invalid original Model ciphertext field')
        decoded = b64decode(encoded, validate=True)
        if b64encode(decoded).decode('ascii') != encoded or not decoded or (
                extent is not None and len(decoded) != extent):
            raise ValueError('Invalid original Model ciphertext extent')
    return {'sealed_sha256': sha256(raw).hexdigest(), 'bytes': len(raw)}


def _file_generation(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError('Expected the original physical Model Store file')
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


def _holding(definition, store, scope, slot, attempt, phase, role):
    return _cid(_canonical({'attempt': 1, 'attempt_cid': attempt, 'phase': phase, 'role': role,
        'run_definition_cid': definition, 'scope_cid': scope, 'slot_cid': slot,
        'store_authority_cid': store, 'version': 'actql-model-scoped-private-holding/0.1'}))


def _retained_model_request_ceiling(database, run_key, run, definition):
    prefix = f'namespace:25:client_task_run_materials:{run_key}:'
    chunks = database.execute("""
        SELECT key, generation,
               CASE WHEN typeof(payload)='blob' AND length(payload) BETWEEN 1 AND 131072
                    THEN payload END
        FROM core_bytes WHERE key >= ? AND key < ? ORDER BY key LIMIT 4
    """, (prefix, prefix[:-1] + ';')).fetchall()
    if (not 1 <= len(chunks) <= 3
            or any(key != prefix + str(index) or generation != 0 or type(body) is not bytes
                   for index, (key, generation, body) in enumerate(chunks))):
        raise ValueError('Unavailable or foreign Run task material chunks')
    material = b''.join(body for _, _, body in chunks)
    if len(material) > 262144 or _cid(material) != _require_cid(run.get('task_materials_cid')):
        raise ValueError('Changed original Run task material digest')
    retained = _object(material)
    environment = _object(retained['check_environment'])
    identity = _require_cid(environment.pop('evidence_bundle_cid', None))
    if (retained['run_id'] != definition['run_id'] or identity != retained['check_environment_cid']
            or _cid(_canonical(environment)) != identity):
        raise ValueError('Foreign retained Model Check environment')
    maximum = environment['host_policy_profile']['capacity']['max_model_request_bytes_per_item']
    if type(maximum) is not int or maximum <= 0:
        raise ValueError('Invalid retained Model request ceiling')
    return min(maximum, _MODEL_STANDARD_REQUEST_BYTES)


def _original_run(database, file_generation, reference):
    definition_cid = _require_cid(reference.get('runDefinitionCid'))
    [(run_key, revision, body)] = _record_rows(database, 'client_runs', 1, require_generation=None)
    run = _object(body)
    definition = _object(run['run_definition'])
    request = _object(run['request'])
    binding = json.loads(run['publication_binding'])
    if (definition['run_definition_cid'] != definition_cid
            or request['authority_scope_cid'] != reference['authorityScopeCid']
            or type(binding) is not list or len(binding) != 4
            or binding[0] != reference['namespaceId']
            or binding[2:] != [str(value) for value in file_generation[:2]]):
        raise ValueError('Model Store Run or physical binding differs from public original')
    return run_key, revision, run, definition, request, _require_cid(binding[1])


def _entry_original(entry_wire, attempt_cid, definition, request, task, provider):
    entry = _object(entry_wire)
    attempt, authority, call = (_object(entry[key]) for key in ('attempt', 'authority', 'call'))
    scope = _require_cid(authority['model_invocation_scope_cid'])
    slot = _require_cid(attempt['slot_cid'])
    if (entry['version'] != 'actql-native-model-call-original/0.1'
            or attempt['version'] != 'actql-model-call-attempt/0.1' or attempt['attempt'] != 1
            or _sealed_identity(attempt) != attempt_cid
            or any(item['run_definition_cid'] != definition for item in (entry, attempt, authority))
            or entry['request_scope_cid'] != request
            or any(item['model_task_cid'] != task for item in (attempt, call, authority))
            or attempt['provider_id'] != provider or authority['connection'] != provider
            or authority['operation'] != 'infer' or call['model_call_slot_cid'] != slot
            or call['fixed_request_cid'] != attempt['fixed_request_cid']
            or authority['fixed_request_cid'] != attempt['fixed_request_cid']
            or attempt['authority_evidence_cid'] != _sealed_identity(authority)
            or entry['slot'] != 0):
        raise ValueError('Foreign original Model Entry')
    return scope, slot, authority['self_cid']


def _attempt_original(entry_wire, settlement_wire, attempt_cid, definition, request, store, task, provider):
    scope, slot, authority = _entry_original(entry_wire, attempt_cid, definition, request, task, provider)
    settlement = _object(settlement_wire)
    if (settlement['version'] != 'actql-native-model-call-settlement-original/0.1'
            or settlement['attempt_cid'] != attempt_cid or settlement['entry_digest'] != _cid(entry_wire)
            or settlement['store_binding'] != store or settlement['run_definition_cid'] != definition
            or settlement['request_scope_cid'] != request or settlement['scope_cid'] != scope
            or settlement['slot'] != 0):
        raise ValueError('Foreign original Model settlement')
    return scope, slot, settlement['evidence'], authority


def _journal_charge(database, scope, expected_bytes, expected_objects):
    charge = database.execute("""
        SELECT reserved_bytes, reserved_objects FROM actql_capacity
        WHERE namespace=? AND reservation_key=?
    """, (_ENTRY, scope)).fetchone()
    if charge != (expected_bytes, expected_objects):
        raise ValueError('Original Model journal charge disagrees with its exact holdings')
    return {'bytes': charge[0], 'objects': charge[1]}


def _held_evidence(evidence, cells, definition, store, scope, slot, attempt, authority):
    observed = {}
    for item in evidence:
        if (set(item) != {'role', 'cid', 'holding_cid'} or item['role'] not in _ROLES
                or item['role'] in observed):
            raise ValueError('Invalid original Model settlement role')
        role = item['role']
        described = _require_cid(item['cid'])
        holding = _holding(definition, store, scope, slot, attempt, 'settled', role)
        if (holding != item['holding_cid'] or holding not in cells
                or (role == 'model_call_attempt' and described != attempt)
                or (role == 'model_dispatch_authority' and described != authority)):
            raise ValueError('Foreign original Model evidence holding')
        observed[role] = {'evidence_cid': described, 'holding_cid': holding,
                          **_sealed_envelope(cells.pop(holding))}
    if set(observed) != _ROLES:
        raise ValueError('Missing original Model attempt accounting or evidence')
    return observed


def _verify_model_accounting(evidence, attempt, slot, envelope, expected_usage, reservation):
    if (type(expected_usage) is not tuple or len(expected_usage) != 2
            or any(value is not None and (type(value) is not int or value < 0)
                   for value in expected_usage)
            or type(reservation) is not dict or set(reservation) != {'tokens', 'cost_units', 'duration_ms'}
            or any(type(value) is not int or value < 0 for value in reservation.values())):
        raise ValueError('Invalid controlled Model accounting oracle')
    accounting = {
        'attempt_cid': attempt, 'slot_cid': slot, 'version': 'actql-model-attempt-accounting/0.1',
        'input_tokens': expected_usage[0], 'output_tokens': expected_usage[1],
        'cost_units': None, 'duration_ms': None, 'reservation': reservation,
        'uncertain_wire_bytes': envelope, 'cumulative_work': 0,
    }
    # The only value unavailable outside the authenticated worker is bounded by
    # the ordinary Model work limit. Match the complete expected canonical body
    # to the exact durable accounting CID. No key or decryption is involved.
    before, marker, after = _canonical(accounting).partition(b'"cumulative_work":0')
    if not marker:
        raise ValueError('Missing canonical Model work field')
    basis = sha256(before + b'"cumulative_work":')
    expected = _require_cid(evidence['evidence_cid']).removeprefix('sha256:')
    matches = []
    for count in range(_MODEL_STANDARD_WORK + 1):
        sample = basis.copy()
        sample.update(str(count).encode('ascii'))
        sample.update(after)
        if sample.hexdigest() == expected:
            matches.append(count)
    if len(matches) != 1:
        raise ValueError('Original Model accounting CID does not match the expected usage')
    accounting['cumulative_work'] = matches[0]
    return accounting


def observe_model_holdings(path: Path, reference: dict, task: str, provider: str,
                           *, expected_usage: tuple[int | None, int | None],
                           reservation: dict[str, int], occurrences: int = 1) -> dict:
    """Check actual retained ciphertext and the exact durable accounting CID."""
    if occurrences not in (1, 2):
        raise ValueError('Unsupported controlled Model occurrence count')
    original = _file_generation(path)
    with closing(sqlite3.connect(path.absolute().as_uri() + '?mode=ro', uri=True)) as database:
        database.execute('BEGIN')
        run_key, _, run, definition_record, request_record, store = _original_run(database, original, reference)
        definition = definition_record['run_definition_cid']
        request = request_record['logical_request_scope_cid']
        request_ceiling = _retained_model_request_ceiling(database, run_key, run, definition_record)
        entries = _records(database, _ENTRY, occurrences)
        settlements = _records(database, _SETTLEMENT, occurrences)
        raws = _records(database, _RAW, occurrences)
        cells = _records(database, _EVIDENCE, occurrences * len(_ROLES))
        observations = []
        for attempt_cid, entry_wire in entries.items():
            if attempt_cid not in settlements:
                raise ValueError('Missing original Model settlement for the Entry')
            terminal = settlements[attempt_cid]
            scope, slot, evidence, authority = _attempt_original(
                entry_wire, terminal, attempt_cid, definition, request, store, task, provider)
            raw = _holding(definition, store, scope, slot, attempt_cid, 'entered', 'model_raw_response')
            if raw not in raws:
                raise ValueError('Missing original Model Raw response holding')
            charge = _journal_charge(database, scope, len(entry_wire) + len(terminal), 2)
            held = _held_evidence(evidence, cells, definition, store, scope, slot, attempt_cid, authority)
            accounting = _verify_model_accounting(held['model_attempt_accounting'], attempt_cid, slot,
                request_ceiling + _MODEL_STANDARD_RESPONSE_BYTES, expected_usage, reservation)
            observations.append({'attempt_cid': attempt_cid, 'scope_cid': scope, 'slot_cid': slot,
                'entry_cid': _cid(entry_wire), 'settlement_cid': _cid(terminal),
                'journal_charge': charge,
                'raw': {'holding_cid': raw, **_sealed_envelope(raws.pop(raw))},
                'evidence': held, 'matched_accounting_preimage': accounting})
        if raws or cells:
            raise ValueError('Unexpected original Model Store holding')
        database.execute('COMMIT')
    if _file_generation(path) != original:
        raise ValueError('Physical Model Store changed during read-only comparison')
    return {'run_definition_cid': definition, 'store_authority_cid': store,
            'observer_reads_evidence_key': False, 'attempts': observations}


def _unknown_state(database, reference, submission_cid, revision, definition, request):
    [(key, generation, body)] = _record_rows(database, 'client_submitted_intents', 1, require_generation=None)
    submitted = _object(body)
    saved_wire = submitted.get('run_state_original')
    if type(saved_wire) is not str:
        raise ValueError('Original Model worker did not durably publish reconciliation state')
    saved = _object(saved_wire)
    admission = _object(submitted['run_admission'])
    if (submitted['phase'] != 'ready' or _cid(_canonical(_object(submitted['reference']))) != submission_cid
            or key != request['caller_request_id'] or _object(admission['request']) != request
            or admission['run_definition_cid'] != reference['runDefinitionCid']
            or saved['run_definition_cid'] != reference['runDefinitionCid'] or saved['manifest'] is not None):
        raise ValueError('Foreign original Model reconciliation state')
    state = _object(saved['state'])
    availability = state.get('result_availability', {})
    answer = availability.get('answer', {})
    stop = {'cancellation_requested': False, 'physical_stop': 'confirmed', 'revision': revision}
    if (state.get('version') != 'actql-run-state/0.1' or state.get('status') != 'needs_reconciliation'
            or state.get('revision') != 0 or submitted.get('run_state_revision') != 0
            or state.get('run_id') != definition['run_id'] or state.get('control') != stop
            or state.get('next_action') != {'kind': 'reconcile_run', 'reason': 'execution_unknown'}
            or state.get('result_available') is not False or set(availability) != {'answer'}
            or answer != {'observed_at': state.get('updated_at'), 'reason': 'not_published', 'state': 'unavailable'}
            or type(state.get('updated_at')) is not str or 'terminal_error' in state):
        raise ValueError('Expected the original stopped Unknown state without a Result')
    observation = {key: value for key, value in state.items() if key not in ('revision', 'updated_at')}
    observation['result_availability'] = {'answer': {'reason': 'not_published', 'state': 'unavailable'}}
    if _object(submitted['run_state_key']) != observation:
        raise ValueError('Original Model observation key disagrees with its retained state')
    return state, {'generation': generation, 'wire_sha256': sha256(body).hexdigest()}


def observe_model_loss(path: Path, reference: dict, submission_cid: str, task: str, provider: str) -> dict:
    """Read the stopped original before and after a separate public cold read."""
    original = _file_generation(path)
    with closing(sqlite3.connect(path.absolute().as_uri() + '?mode=ro', uri=True)) as database:
        database.execute('BEGIN')
        _, revision, _, definition, request, store = _original_run(database, original, reference)
        state, submitted = _unknown_state(database, reference, submission_cid, revision, definition, request)
        [(attempt, entry_wire)] = _records(database, _ENTRY, 1).items()
        scope, slot, _ = _entry_original(entry_wire, attempt, definition['run_definition_cid'],
                                         request['logical_request_scope_cid'], task, provider)
        for namespace in (_SETTLEMENT, _RAW, _EVIDENCE):
            _records(database, namespace, 0)
        charge = _journal_charge(database, scope, len(entry_wire), 1)
        database.execute('COMMIT')
    if _file_generation(path) != original:
        raise ValueError('Physical Model Store changed during read-only comparison')
    return {'run_definition_cid': definition['run_definition_cid'], 'store_authority_cid': store,
            'state': state, 'submitted_intent': submitted, 'entry_cid': _cid(entry_wire),
            'attempt_cid': attempt, 'scope_cid': scope, 'slot_cid': slot, 'journal_charge': charge,
            'raw_count': 0, 'settlement_count': 0, 'evidence_count': 0}
