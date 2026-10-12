"""Closed wire admission, separate from Host-owned execution decisions."""
import json
import math
from pathlib import Path
import re
import unicodedata
from ._values import SAFE_INTEGER

CONTRACT = json.loads(Path(__file__).with_name('_contract.json').read_text(encoding='utf-8'))
SCHEMAS = CONTRACT['schemas']


def utf16_length(text):
    return len(text.encode('utf-16-le', 'strict')) // 2


def _equal(left, right):
    # Python bool is an int subclass; JSON constants never conflate them.
    if type(left) is bool or type(right) is bool:
        return type(left) is type(right) and left == right
    return left == right


def valid(value, schema):
    if isinstance(schema, str):
        schema = SCHEMAS[schema]
    if '$ref' in schema:
        return valid(value, schema['$ref'])
    if 'oneOf' in schema and sum(valid(value, rule) for rule in schema['oneOf']) != 1:
        return False
    if 'not' in schema and valid(value, schema['not']):
        return False
    if 'if' in schema and valid(value, schema['if']) and not valid(value, schema['then']):
        return False
    if 'allOf' in schema and not all(valid(value, rule) for rule in schema['allOf']):
        return False
    if 'const' in schema and not _equal(value, schema['const']):
        return False
    if 'enum' in schema and not any(_equal(value, item) for item in schema['enum']):
        return False
    if type(value) in (int, float):
        if not math.isfinite(value) or value == 0 and math.copysign(1, value) < 0:
            return False
        if value < schema.get('minimum', -math.inf) or value > schema.get('maximum', math.inf):
            return False
    if type(value) is str:
        try:
            length = utf16_length(value)
        except UnicodeError:
            return False
        if len(value) < schema.get('minLength', 0) or length > schema.get('maxLength', math.inf):
            return False
        if 'pattern' in schema and re.search(schema['pattern'], value, re.ASCII) is None:
            return False
    kind = schema.get('type')
    if kind == 'string':
        return type(value) is str
    if kind == 'number':
        return type(value) in (int, float)
    if kind == 'integer':
        return type(value) in (int, float) and abs(value) <= SAFE_INTEGER and int(value) == value
    if kind == 'boolean':
        return type(value) is bool
    if kind == 'array':
        return (type(value) is list and schema.get('minItems', 0) <= len(value) <= schema.get('maxItems', math.inf)
                and all(valid(item, schema['items']) for item in value)
                and (not schema.get('uniqueItems') or len(set(value)) == len(value)))
    if type(value) is dict and not schema.get('minProperties', 0) <= len(value) <= schema.get('maxProperties', math.inf):
        return False
    if kind == 'object' or 'properties' in schema or 'required' in schema:
        if type(value) is not dict or not set(schema.get('required', ())).issubset(value):
            return False
        properties = schema.get('properties', {})
        extra = set(value) - set(properties)
        additional = schema.get('additionalProperties', True)
        if additional is False and extra:
            return False
        if isinstance(additional, dict) and not all(valid(value[key], additional) for key in extra):
            return False
        if 'propertyNames' in schema and not all(valid(key, schema['propertyNames']) for key in value):
            return False
        return all(key not in value or valid(value[key], field) for key, field in properties.items())
    return True


def bounded_text(value, limit=256):
    return valid(value, {'type': 'string', 'minLength': 1, 'maxLength': limit,
                         'pattern': r'^[^\u0000-\u001f\u007f]+$'})


def epoch(value):
    return valid(value, 'submission_epoch') and value['expiresAt'] > value['notBefore']


def submission_ref(value):
    if not valid(value, 'submission_ref') or not epoch(value['epoch']):
        return False
    nonce = value['nonce']
    return (unicodedata.normalize('NFC', nonce) == nonce and len(nonce.encode('utf-8')) <= 256
            and re.search(r'[\u0080-\u009f]', nonce) is None)


def restart(value, fresh):
    return (valid(value, 'submission_restart') and submission_ref(value['submissionRef']) and submission_ref(fresh)
            and value['submissionRef']['epoch']['authorityScopeCid'] == fresh['epoch']['authorityScopeCid']
            and value['submissionRef']['epoch']['expiresAt'] < fresh['epoch']['expiresAt'])


def negotiated(value, schema, selected):
    if not valid(value, schema) or not valid(selected, 'connection'):
        return False
    rules = CONTRACT['response_rules'][schema]
    if any(value.get(key) != selected.get(key) for key in rules['matchConnection']):
        return False
    if any(selected.get(key) == expected and value.get(key) != expected
           for key, expected in rules['requireRequested'].items()):
        return False
    return schema != 'profile' or 'submissionEpoch' not in value or epoch(value['submissionEpoch'])


def correlated(value, schema, request_id):
    rules = CONTRACT['request_response_rules'][schema]
    return (any(valid(value, name) for name in rules['schemas'])
            and value.get(rules['matchRequest']) == request_id)


def check_outcome(value):
    if not valid(value, 'check_outcome') or value['outcome_schema_cid'] != CONTRACT['check_outcome_schema_cid']:
        return False
    report = value.get('report', value.get('partial_report'))
    if report is None:
        return True
    documents = {item['document_id']: item for item in report['inputs']}
    if len(documents) != len(report['inputs']):
        return False
    if 'program' in documents:
        if documents['program']['kind'] != 'structured' or {'source', 'parameter_declarations'} & documents.keys():
            return False
    elif documents.get('source', {}).get('kind') != 'text':
        return False
    if any(item['kind'] != 'structured' for key, item in documents.items() if key != 'source'):
        return False
    for reason in report['reasons'] + report['requirements'] + report['coverage']['limits']:
        location = reason.get('location')
        if location is not None:
            doc = documents.get(location['document_id'])
            if doc is None or (doc['revision'], doc['kind']) != (location['revision'], location['kind']):
                return False
            if location['kind'] == 'text' and not 0 <= location['start_byte'] <= location['end_byte'] <= doc['byte_length']:
                return False
        for fix in reason.get('fixes', []):
            doc = documents.get(fix['target']['document_id'])
            if doc is None or doc['kind'] != 'text' or doc['revision'] != fix['target']['revision']:
                return False
            if any(edit['start_byte'] != doc['byte_length'] or edit['end_byte'] != doc['byte_length'] for edit in fix['edits']):
                return False
    return True


def submission_outcome(value, selected, expected, intent_cid=None, unresolved=None, *, lookup=False):
    if not submission_ref(expected) or not valid(value, 'submission_lookup' if lookup else 'submission_outcome'):
        return False
    if value['submissionRef'] != expected or intent_cid is not None and value['intentCid'] != intent_cid:
        return False
    if 'unresolvedHistory' in value and not restart(value['unresolvedHistory'], expected):
        return False
    if not lookup and value.get('unresolvedHistory') != unresolved:
        return False
    if 'checkObservation' in value and not check_outcome(value['checkObservation']):
        return False
    if value['kind'] == 'ready':
        return (negotiated(value['admission'], 'admission', selected)
                and value['admission']['ref']['authorityScopeCid'] == expected['epoch']['authorityScopeCid'])
    if value['kind'] == 'held':
        return correlated(value['held'], 'held', expected['nonce'])
    return True


def submission_attempt(value, selected, body):
    if not valid(value, 'submission_attempt') or value['attemptRef'] != body['attemptRef']:
        return False
    if value['kind'] in ('recorded', 'already_satisfied'):
        return (submission_outcome(value['outcome'], selected, body['submissionRef'], body['intentCid'], body.get('unresolvedHistory'))
                and (value['kind'] != 'already_satisfied' or value['outcome']['kind'] != 'preparing'))
    return (value['kind'] == 'refused' and value['reason'] == 'authorization'
            or value.get('submissionRef') == body['submissionRef'] and value.get('intentCid') == body['intentCid'])


def cancellation(value, expected):
    return (valid(value, 'cancellation') and valid(expected, 'cancellation_ref')
            and value['cancelRef'] == expected and all(value['ref'][key] == expected[key] for key in value['ref'])
            and value['revision'] >= expected['expectedRevision']
            and (value['kind'] != 'accepted' or value['revision'] > expected['expectedRevision']))


def cancellation_attempt(value, expected, attempt):
    if not valid(value, 'cancellation_attempt') or value['attemptRef'] != attempt:
        return False
    if value['kind'] in ('accepted', 'already_satisfied'):
        return (cancellation(value['cancellation'], expected)
                and (value['cancellation']['kind'] == 'accepted' if value['kind'] == 'accepted'
                     else value['cancellation']['kind'] in ('already_requested', 'already_terminal')))
    return 'cancelRef' not in value or value['cancelRef'] == expected


def cancellation_lookup(value, expected):
    return (valid(value, 'cancellation_lookup') and
            (cancellation(value['cancellation'], expected) if value['kind'] == 'found' else value['cancelRef'] == expected))


def valid_body(operation, body):
    keys = CONTRACT['operations'].get(operation)
    if keys is None or type(body) is not dict:
        return False
    if operation == 'check' and body.get('scope') == 'template_only':
        keys = [key for key in keys if key != 'parameters']
    if set(body) != set(keys) or not valid(body['connection'], 'connection'):
        return False
    if operation == 'connect':
        return True
    if operation == 'lookup-submission':
        return submission_ref(body['submissionRef'])
    if operation in ('submit-intent', 'restart-intent'):
        if not (submission_ref(body['submissionRef']) and valid(body['intentCid'], {'type': 'string', 'pattern': '^sha256:[0-9a-f]{64}$'})
                and valid(body['attemptRef'], 'operation_attempt_ref') and body['attemptRef']['operation'] == 'submit'):
            return False
        if operation == 'restart-intent' and not restart(body['unresolvedHistory'], body['submissionRef']):
            return False
        return valid_body('submit', {key: body[key] for key in ('connection', 'kind', 'input', 'parameters')}
                          | {'requestId': body['submissionRef']['nonce']}) and (body['parameters'] is None or type(body['parameters']) is dict)
    if operation in ('submit', 'check'):
        is_check = operation == 'check'
        if is_check:
            if body['scope'] not in ('template_only', 'bound_input') or body['kind'] not in ('text', 'program'):
                return False
            if body['scope'] == 'bound_input' and body['parameters'] is not None and type(body['parameters']) is not dict:
                return False
        elif not bounded_text(body['requestId']) or body['kind'] not in ('aql', 'program'):
            return False
        item = body['input']
        if body['kind'] == 'program':
            return type(item) is dict
        if type(item) is not dict or set(item) not in ({'text', 'format'}, {'text', 'format', 'parameterDeclarations'}):
            return False
        if not valid(item['text'], {'type': 'string', 'minLength': 1, 'maxLength': 65536}) or '\0' in item['text']:
            return False
        formats = ('aql-text', 'sql') if is_check else CONTRACT['source_formats']
        return (item['format'] in formats and ('parameterDeclarations' not in item or
                item['format'] in ('aql-text', 'sql') and type(item['parameterDeclarations']) is dict))
    if operation in ('lookup-request', 'cancel-request'):
        return bounded_text(body['requestId'])
    if operation == 'checkpoints':
        return valid(body['limit'], {'type': 'integer', 'minimum': 1, 'maximum': 100}) and (body['after'] == '' or bounded_text(body['after'], 512))
    if operation == 'checkpoint-review':
        return valid(body['checkpointCid'], {'type': 'string', 'pattern': '^sha256:[0-9a-f]{64}$'}) and valid(body['maxBytes'], {'type': 'integer', 'minimum': 1, 'maximum': 1048576})
    if operation == 'resolve':
        items = body['items']
        return (type(items) is list and 1 <= len(items) <= 16 and all(valid(item, 'resolve_item') for item in items)
                and len({item['checkpointCid'] for item in items}) == len(items))
    if 'ref' not in body or not valid(body['ref'], 'run_ref'):
        return False
    if operation in ('cancel', 'lookup-cancellation'):
        return (valid(body['ref'] | {key: body[key] for key in ('cancelId', 'expectedRevision')}, 'cancellation_ref')
                and (operation != 'cancel' or valid(body['attemptRef'], 'operation_attempt_ref') and body['attemptRef']['operation'] == 'cancel'))
    if operation in ('read', 'result-describe', 'delivery-attempt'):
        if not bounded_text(body['resultName']) or not bounded_text(body['attemptId']):
            return False
        if operation != 'delivery-attempt' and body['format'] not in ('json', 'jsonl', 'csv'):
            return False
        if operation == 'result-describe':
            return all(valid(body[key], {'type': 'integer', 'minimum': 1, 'maximum': limit})
                       for key, limit in {'maxWireBytes': 1048576, 'maxNodes': 10000, 'maxDepth': 64}.items())
        return True
    if operation == 'wait':
        return body['until'] is None or bounded_text(body['until'], 128)
    return operation in ('attach', 'status', 'reconcile')
