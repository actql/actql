"""Presentation custody for original calls; no checking or execution authority."""
import re
import weakref
from ._errors import ClientError
from ._check_observation import CheckObservation
from ._values import Observation, freeze, snapshot, thaw, wire_bytes
from ._wire import CONTRACT, utf16_length, valid

_inputs = weakref.WeakKeyDictionary()
_submission_checks = weakref.WeakKeyDictionary()


def _node_exists(value, pointer):
    if type(pointer) is not str or utf16_length(pointer) > 4096 or re.fullmatch(r'(?:/(?:[^~]|~[01])*)*', pointer) is None:
        return False
    if not pointer:
        return True
    for token in pointer[1:].split('/'):
        key = token.replace('~1', '/').replace('~0', '~')
        if type(value) is list:
            if re.fullmatch(r'0|[1-9][0-9]*', key) is None or int(key) >= len(value):
                return False
            value = value[int(key)]
        elif type(value) is dict and key in value:
            value = value[key]
        else:
            return False
    return True


def bind_check(value, body):
    observation = CheckObservation(value)
    report = value.get('report', value.get('partial_report'))
    if report is None:
        return observation
    if report['scope']['kind'] != body.get('scope', 'bound_input'):
        raise ClientError('InvalidHostCheckInputBinding')
    original = ({'program': {'kind': 'structured', 'value': body['input']}} if body['kind'] == 'program'
                else {'source': {'kind': 'text', 'text': body['input']['text']}})
    if body['kind'] != 'program' and 'parameterDeclarations' in body['input']:
        original['parameter_declarations'] = {'kind': 'structured', 'value': body['input']['parameterDeclarations']}
    if body.get('parameters') is not None:
        original['parameters'] = {'kind': 'structured', 'value': body['parameters']}
    if len(original) != len(report['inputs']):
        raise ClientError('InvalidHostCheckInputBinding')
    captured = {}
    for doc in report['inputs']:
        item = original.get(doc['document_id'])
        if item is None or doc['kind'] != item['kind']:
            raise ClientError('InvalidHostCheckInputBinding')
        raw = item['text'].encode('utf-8') if item['kind'] == 'text' else wire_bytes(item['value'])
        if len(raw) != doc['byte_length']:
            raise ClientError('InvalidHostCheckInputBinding')
        captured[doc['document_id']] = freeze(snapshot(item | {'document_id': doc['document_id'], 'revision': doc['revision']}))
    _inputs[observation] = captured
    for reason in report['reasons'] + report['requirements'] + report['coverage']['limits']:
        if 'location' in reason and resolve_check_location(observation, reason['location']) is None:
            del _inputs[observation]
            raise ClientError('InvalidHostCheckInputBinding')
    return observation


def get_check_input(observation, document_id, revision=None):
    original = _inputs.get(observation, {}).get(document_id) if isinstance(observation, Observation) else None
    return original if original is not None and (revision is None or original['revision'] == revision) else None


def resolve_check_location(observation, location, current_input=None):
    if not hasattr(location, 'get'):
        return None
    original = get_check_input(observation, location.get('document_id'), location.get('revision'))
    if original is None or location.get('kind') != original['kind']:
        return None
    if current_input is not None and thaw(current_input) != thaw(original):
        return None
    original_value = thaw(original)
    if original['kind'] == 'structured':
        return freeze(thaw(location) | {'input': original}) if _node_exists(original_value['value'], location.get('pointer')) else None
    raw = original['text'].encode('utf-8')
    start, end = location.get('start_byte'), location.get('end_byte')
    if not all(valid(at, {'type': 'integer', 'minimum': 0, 'maximum': len(raw)}) for at in (start, end)) or start > end:
        return None
    start, end = int(start), int(end)
    try:
        raw[:start].decode('utf-8', 'strict')
        text = raw[start:end].decode('utf-8', 'strict')
    except UnicodeError:
        return None
    return freeze(thaw(location) | {'input': original, 'text': text})


def resolve_check_text_range(observation, location, current_input=None):
    resolved = resolve_check_location(observation, location, current_input)
    if resolved is None or resolved['kind'] != 'text':
        return None
    raw = resolved['input']['text'].encode('utf-8')
    def position(at):
        at = int(at)
        # CRLF is one line break; byte offsets and UTF-16 columns remain exact.
        if at > 0 and at < len(raw) and raw[at-1:at+1] == b'\r\n':
            return None
        prefix = raw[:at].decode('utf-8')
        line = 0
        column = 0
        previous_cr = False
        for char in prefix:
            if char == '\r':
                line += 1
                column = 0
            elif char == '\n':
                if not previous_cr:
                    line += 1
                column = 0
            else:
                column += utf16_length(char)
            previous_cr = char == '\r'
        return {'line': line, 'character': column}
    start, end = position(resolved['start_byte']), position(resolved['end_byte'])
    return freeze({'start': start, 'end': end}) if start is not None and end is not None else None


def retain_submission_check(error, value, body):
    _submission_checks[error] = bind_check(value, body)


def get_submission_check_observation(error):
    return _submission_checks.get(error) if isinstance(error, ClientError) else None


def explain_check_reason(reason):
    """Safe catalog prose does not establish a verdict or input custody."""
    code = reason.get('code') if hasattr(reason, 'get') else None
    entry = next((item for item in CONTRACT['reasons']['entries'] if item['code'] == code), None)
    if entry is None:
        return freeze({'kind': 'unknown', 'summary': 'No supported explanation is available for this reason.'})
    presentation = entry['presentation']
    selected = None
    facts = reason.get('facts', {})
    for variant in presentation['variants']:
        if all(facts.get(key) in expected if type(expected) is list else facts.get(key) == expected
               for key, expected in variant['when'].items()):
            selected = variant
            break
    if selected is None:
        selected = presentation.get('default')
    if selected is None:
        return freeze({'kind': 'unknown', 'summary': 'No supported explanation is available for this reason.'})
    summary, hint = selected['english']
    return freeze({'kind': 'known', 'summary': summary, 'hint': hint})


def get_check_fixes(observation):
    if not isinstance(observation, Observation) or observation not in _inputs or observation['outcome'] != 'completed':
        return None
    return tuple(fix for reason in observation['report']['reasons'] for fix in reason.get('fixes', ()))
