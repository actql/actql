"""Independent readback of this fixture's closed Local publication metadata."""

import hashlib
import json
import re


def canonical_bytes(value):
    # These fixed fixture identities and schema/contract bodies use ASCII and
    # integral counts. Refuse a different encoding domain instead of widening
    # this independent encoder into a second publication parser.
    body = json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)
    assert body.isascii()
    return body.encode('ascii')


def sha256(body):
    return hashlib.sha256(body).hexdigest()


def content_cid(value):
    return 'sha256:' + sha256(canonical_bytes(value))


def require_cid(value):
    assert type(value) is str and re.fullmatch(r'sha256:[0-9a-f]{64}', value)
    return value


def read_published_result_schemas(connection, run, run_id, oracle):
    """Follow only the actual Run's index and exact named Result dependencies."""
    assert connection.in_transaction and 1 <= len(oracle) <= 8

    def stored_bytes(namespace, address, maximum):
        key = f'namespace:{len(namespace.encode("utf-8"))}:{namespace}:{address}'
        row = connection.execute(
            "SELECT generation, CASE WHEN typeof(payload) = 'blob' AND "
            "length(payload) BETWEEN 1 AND ? THEN payload END "
            "FROM core_bytes WHERE key = ? COLLATE BINARY",
            (maximum, key),
        ).fetchone()
        assert row is not None and row[0] == 0 and type(row[1]) is bytes, key
        return row[1]

    def contract(kind, cid):
        raw = stored_bytes('publication_contract', require_cid(cid), 32768)
        value = json.loads(raw)
        assert type(value) is dict and canonical_bytes(value) == raw
        assert value['version'] == 'actql-' + kind.replace('_', '-') + '/0.1'
        identity = kind + '_cid'
        preimage = dict(value)
        assert preimage.pop(identity) == cid and content_cid(preimage) == cid
        return value

    namespace = run['namespaceId']
    scope = require_cid(run['authorityScopeCid'])
    run_definition_cid = require_cid(run['runDefinitionCid'])
    scope_key = {'namespace_id': namespace, 'authority_scope_cid': scope,
                 'run_definition_cid': run_definition_cid, 'version': 'actql-public-index-key/0.1'}
    address = sha256(canonical_bytes(scope_key))
    index_cid = stored_bytes('public_index', address, 71).decode('ascii')
    index = contract('public_index_entry', index_cid)
    assert (index['namespace_id'], index['authority_scope_cid'], index['run_definition_cid']) == (
        namespace, scope, run_definition_cid,
    )
    assert contract('run_definition', run_definition_cid)['run_id'] == run_id
    invocation_cid = require_cid(index['invocation_cid'])
    manifest_cid = index['result_manifest_cid']
    manifest = contract('result_manifest', manifest_cid)
    assert manifest['run_definition_cid'] == run_definition_cid and manifest['invocation_cid'] == invocation_cid
    assert type(manifest['results']) is dict and set(manifest['results']) == set(oracle)

    binding_cids = index['durable_result_binding_cids']
    assert type(binding_cids) is list and len(set(binding_cids)) == len(binding_cids) == len(oracle)
    bindings = {}
    for cid in binding_cids:
        binding = contract('durable_result_binding', cid)
        definition_cid = require_cid(binding['result_definition_cid'])
        assert definition_cid not in bindings
        assert binding['run_definition_cid'] == run_definition_cid and binding['invocation_cid'] == invocation_cid
        bindings[definition_cid] = binding

    results = {}
    for name, wanted in oracle.items():
        artifact = manifest['results'][name]
        artifact_cid = artifact['result_artifact_cid']
        assert artifact == contract('result_artifact', artifact_cid)
        assert artifact['invocation_cid'] == invocation_cid and artifact['actual_completeness'] == 'complete'
        assert type(artifact['actual_row_count']) is int and artifact['actual_row_count'] == len(wanted['rows'])
        definition_cid = artifact['result_definition_cid']
        assert contract('result_definition', definition_cid)['result_name'] == name
        binding = bindings.pop(definition_cid)
        assert type(binding['row_count']) is int and binding['row_count'] == artifact['actual_row_count']
        for field in ('result_schema_cid', 'logical_result_cid', 'ordering_evidence_cid',
                      'effective_retention_policy_cid'):
            assert require_cid(binding[field]) == artifact[field]

        schema_cid = artifact['result_schema_cid']
        raw_schema = stored_bytes('result_schema', schema_cid, 32768)
        assert 'sha256:' + sha256(raw_schema) == schema_cid
        expected_fields = {column['name']: column['contract'] for column in wanted['columns']}
        expected_order = [column['name'] for column in wanted['columns']]
        assert len(expected_fields) == len(expected_order) and binding['result_fields'] == expected_order
        assert raw_schema == canonical_bytes(expected_fields)
        fields = json.loads(raw_schema)
        results[name] = {'artifactCid': artifact_cid, 'definitionCid': definition_cid,
                         'schemaCid': schema_cid, 'bindingCid': binding['durable_result_binding_cid'],
                         'columns': [{'name': field, 'contract': fields[field]} for field in binding['result_fields']]}

    assert not bindings and len({result['artifactCid'] for result in results.values()}) == len(results)
    return {'publicIndexCid': index_cid, 'manifestCid': manifest_cid, 'invocationCid': invocation_cid,
            'results': results}
