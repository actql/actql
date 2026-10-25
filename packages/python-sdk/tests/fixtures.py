"""Independent wire fixtures shared by both facades. No execution simulation."""
from copy import deepcopy

AUTHORITY = 'sha256:' + 'a' * 64
RUN_REF = {'namespaceId': 'python-fixture', 'authorityScopeCid': AUTHORITY, 'runDefinitionCid': 'sha256:' + 'd' * 64}
EPOCH = {'version': 'actql-submission-epoch/0.1', 'authorityScopeCid': AUTHORITY,
         'epochNonce': 'b' * 64, 'notBefore': 1800000000000, 'expiresAt': 1800000001000, 'authenticator': 'c' * 64}
PROFILE = {'version': 'actql-client-host/0.1', 'mode': 'remote', 'owner': 'remote', 'durability': 'durable',
           'scopeRef': 'python-fixture', 'submissionEpoch': EPOCH, 'capabilities': [], 'limits': {
               'maxReadWireBytes': 4096, 'maxRowWireBytes': 1024, 'maxRowRetainedValueBytes': 2048,
               'maxRetainedValueBytes': 4096, 'maxRows': 100, 'maxBatchRows': 10, 'maxBatchRetainedValueBytes': 2048}}
ADMISSION = {'ref': RUN_REF, 'durability': 'durable', 'revision': 0}
REVISION = 'rev:' + '1' * 64
SELECTED = {'mode': 'remote', 'owner': 'remote', 'durability': 'durable', 'consentRefs': [], 'runners': []}


def check_report(*, kind='text', byte_length=10, pointer='', start=0, end=4):
    location = ({'kind': 'text', 'document_id': 'source', 'revision': REVISION, 'precision': 'exact', 'start_byte': start, 'end_byte': end}
                if kind == 'text' else {'kind': 'structured', 'document_id': 'program', 'revision': REVISION, 'pointer': pointer})
    return {'version': 'actql-check-outcome/0.1',
            'reason_schema_cid': 'sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511',
            'outcome_schema_cid': 'sha256:ce7df95dc9d069472f6dd61273acb6e5d09aba605347cddda5c4a23c6e5e52f6',
            'outcome': 'completed', 'report': {'context_ref': 'ctx:independent-python', 'scope': {'kind': 'bound_input'},
                'verdict': 'invalid', 'runnable': {'verdict': 'no', 'reasons': [{'code': 'query_lexical_invalid' if kind == 'text' else 'program_structure_invalid'}]}, 'inputs': [{'document_id': location['document_id'], 'revision': REVISION,
                    'kind': location['kind'], 'byte_length': byte_length}],
                'reasons': [{'code': 'query_lexical_invalid' if kind == 'text' else 'program_structure_invalid',
                             'facts': {'issue': 'unexpected_token' if kind == 'text' else 'wrong_type'}, 'location': location}],
                'requirements': [], 'coverage': {'limits': [], 'unresolved': []}}}


def reference(nonce='original'):
    return {'epoch': deepcopy(EPOCH), 'nonce': nonce}


def ready(request):
    return {'kind': 'recorded', 'attemptRef': request['attemptRef'], 'outcome': {
        'kind': 'ready', 'submissionRef': request['submissionRef'], 'intentCid': request['intentCid'], 'admission': deepcopy(ADMISSION)}}
