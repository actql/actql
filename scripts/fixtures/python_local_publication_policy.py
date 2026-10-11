"""Assemble the independently frozen Local retention input, not a Core proof."""
import hashlib
import json
from pathlib import Path


def publication_policy(root: Path):
    expected = json.loads((root / 'scripts/fixtures/python-local-result-publication.json').read_text())
    # Preserve the independently fixed preimage and CID. Only the contract's
    # declared self-identity field is added to its admitted wire.
    assert 'sha256:' + hashlib.sha256(expected['retention_preimage'].encode()).hexdigest() == expected['retention_policy_cid']
    retention = json.loads(expected['retention_preimage'])
    retention['effective_retention_policy_cid'] = expected['retention_policy_cid']
    return expected, json.dumps(retention, sort_keys=True, separators=(',', ':'))
