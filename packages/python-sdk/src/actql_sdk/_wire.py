"""Closed wire admission, separate from Host-owned execution decisions."""
import re
import unicodedata
from ._wire_codec import (CONTRACT, SCHEMAS, valid as valid, utf16_length, correlated, check_outcome, valid_run_wait as valid_run_wait,
                          negotiated as negotiated_contract)


def bounded_text(value, limit=256):
    return valid(value, {'type': 'string', 'minLength': 1, 'maxLength': limit,
                         'pattern': r'^[^\u0000-\u001f\u007f]+(?![\s\S])'})


def epoch(value):
    return valid(value, 'submission_epoch') and value['expiresAt'] > value['notBefore']


def submission_ref(value):
    if not valid(value, 'submission_ref') or not epoch(value['epoch']):
        return False
    return _canonical_submission_text(value['nonce'])


def _canonical_submission_text(value):
    # Same existing registered class as the explicit-epoch nonce and scoped
    # name. Validation rejects invalid Unicode; never normalize or repair it.
    return (unicodedata.normalize('NFC', value) == value and len(value.encode('utf-8')) <= 256
            and re.search(r'[\u0080-\u009f]', value) is None)


def submission_name(value):
    return valid(value, 'submission_name') and _canonical_submission_text(value)


def restart(value, fresh):
    return (valid(value, 'submission_restart') and submission_ref(value['submissionRef']) and submission_ref(fresh)
            and value['submissionRef']['epoch']['authorityScopeCid'] == fresh['epoch']['authorityScopeCid']
            and value['submissionRef']['epoch']['expiresAt'] < fresh['epoch']['expiresAt'])


def negotiated(value, schema, selected):
    return (negotiated_contract(value, schema, selected)
            and (schema != 'profile' or 'submissionEpoch' not in value or epoch(value['submissionEpoch'])))


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


def named_submission_attempt(value, selected, body):
    if (not valid(selected, 'connection') or not submission_name(body['requestName'])
            or not submission_ref(body['submissionRef'])
            or not valid(body['attemptRef'], 'operation_attempt_ref') or body['attemptRef']['operation'] != 'submit'
            or not valid(value, 'named_submission_attempt')
            or any(value[key] != body[key] for key in ('requestName', 'intentCid', 'attemptRef'))):
        return False
    if value['kind'] != 'observed':
        return True
    outcome = value['outcome']
    original = outcome['submissionRef']
    if (not submission_ref(original)
            or original['epoch']['authorityScopeCid'] != body['submissionRef']['epoch']['authorityScopeCid']):
        return False
    if outcome['kind'] == 'unresolvable':
        return submission_outcome(outcome, selected, original, lookup=True)
    # There is no restart request in this named envelope. Validate any retained
    # history against the returned original, without inventing a requested one.
    return submission_outcome(outcome, selected, original, body['intentCid'], outcome.get('unresolvedHistory'))


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
    optional = CONTRACT.get('request_optional_fields', {}).get(operation, {})
    if (not set(keys) <= set(body) or set(body) - set(keys) - set(optional)
            or any(not valid(body[key], rule) for key, rule in optional.items() if key in body)
            or not valid(body['connection'], 'connection')):
        return False
    if operation == 'connect':
        return True
    if operation == 'lookup-submission':
        return submission_ref(body['submissionRef'])
    if operation == 'submit-named-intent':
        return (submission_name(body['requestName'])
                and valid_body('submit-intent', {key: value for key, value in body.items() if key != 'requestName'}))
    if operation in ('submit-intent', 'restart-intent'):
        if not (submission_ref(body['submissionRef']) and valid(body['intentCid'], {'type': 'string', 'pattern': '^sha256:[0-9a-f]{64}$'})
                and valid(body['attemptRef'], 'operation_attempt_ref') and body['attemptRef']['operation'] == 'submit'):
            return False
        if operation == 'restart-intent' and not restart(body['unresolvedHistory'], body['submissionRef']):
            return False
        submitted = {key: body[key] for key in ('connection', 'kind', 'input', 'parameters')}
        for key in CONTRACT.get('request_optional_fields', {}).get('submit', {}):
            if key in body:
                submitted[key] = body[key]
        return valid_body('submit', submitted | {'requestId': body['submissionRef']['nonce']}) and (body['parameters'] is None or type(body['parameters']) is dict)
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
        # The selected Host owns preparation demand; wire shape has no separate
        # UTF-16 Program ceiling. Transport ingress policy remains independent.
        if not valid(item['text'], {'type': 'string', 'minLength': 1}) or '\0' in item['text']:
            return False
        formats = ('aql', 'aql-text', 'sql') if is_check else CONTRACT['source_formats']
        return (item['format'] in formats and ('parameterDeclarations' not in item or
                item['format'] in ('aql', 'aql-text', 'sql') and type(item['parameterDeclarations']) is dict))
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
        return ((body['until'] is None or bounded_text(body['until'], 128))
                and (body['since'] is None or valid(body['since'], SCHEMAS['run_state']['properties']['revision'])))
    return operation in ('attach', 'status', 'reconcile')
