"""Prepared private ABI34 consumer; unexecuted without its matching module.

This read-only contract projection does not install a Store or grant publication.
"""
import json
from pathlib import Path


def check_payload_binding(fixture, record, original_wire, configuration, denied,
                          call, status, ticket):
    root = Path(__file__).parent
    expected = json.loads((root / 'python-local-payload-binding.json').read_text())
    semantic = json.loads((root / 'python-local-result-storage-binding.json').read_text())
    original = json.loads(original_wire)
    assert original['state'] == 'sealed' and original['revision'] == '4'
    cases = []
    child = call('payload_binding', 'reserve', record, ticket(), expected['physical_copy_bytes'])
    assert child > 0, ('Original Sealed binding reserve', child)
    try:
        status('payload_binding', 'validate', -33, child, configuration)
        status('payload_binding', 'produce', -32, child, denied)
        status('payload_binding', 'produce', 0, child, configuration)

        def output():
            status('payload_binding', 'validate', 0, child, configuration)
            size = call('payload_binding', 'length', child)
            assert 0 < size <= expected['max_bytes']
            return bytes(fixture.call('byte', child, i) for i in range(size))

        wire = output()
        body = json.loads(wire)
        for field in ('byte_count', 'physical_sha256', 'result_schema_cid',
                      'codec_contract_cid', 'row_count', 'result_fields',
                      'material_generation_cid', 'store_authority_cid'):
            assert body[field] == semantic[field], (field, body[field], semantic[field])
        cases.append(expected['cases'][0])
        queries = fixture.queries
        status('payload_binding', 'produce', -32, child, denied)
        status('payload_binding', 'validate', -32, child, denied)
        status('payload_binding', 'produce', 0, child, configuration)
        assert output() == wire and fixture.queries == queries == 3
        status('payload_binding', 'reserve', -3, record, ticket(), expected['physical_copy_bytes'])
        status('payload_binding', 'reserve', -2, child, ticket(), expected['physical_copy_bytes'])
        cases.append(expected['cases'][1])
        held = fixture.call('allocated')
        status('payload_record', 'close', -9, record)
        status('payload_binding', 'validate', -5, child, configuration)
        fixture.cleanup_ready = False
        status('payload_binding', 'close', -9, child)
        assert fixture.call('allocated') == held
        cases.append(expected['cases'][2])
        fixture.cleanup_ready = True
        status('payload_binding', 'close', 0, child)
        status('payload_binding', 'close', -2, child)
        status('payload_binding', 'validate', -2, child, configuration)
        assert fixture.call('allocated') == held - (2 * expected['max_bytes'] + expected['physical_copy_bytes'])
        assert json.loads(original_wire) == original and fixture.queries == queries
        cases.append(expected['cases'][3])
    finally:
        fixture.cleanup_ready = True
        remaining = call('payload_binding', 'close', child)
        assert remaining in (0, -2), ('Original binding cleanup pending', remaining)
    assert cases == expected['cases']
    return cases
