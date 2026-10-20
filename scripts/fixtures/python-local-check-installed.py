"""Exercise the documented public Check on a new normal installed Local Host.

This fixture supplies no Core, runtime path, resource callback or transport.
It prepares no Run and does not read or repair an earlier installation.
"""
from __future__ import annotations

import argparse
import importlib.metadata
import json
import os
from pathlib import Path
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-dir', type=Path, required=True)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--await-close-observation', action='store_true')
    options = parser.parse_args()
    if options.state_dir.exists() or options.result.exists():
        raise RuntimeError('Check acceptance requires a new installation and result')

    import actql

    if not Path(actql.__file__).resolve().is_relative_to(Path(sys.prefix).resolve()):
        raise RuntimeError('Check acceptance requires the normal installed facade')
    versions = {name: importlib.metadata.version(name)
                for name in ('actql', 'actql-sdk', 'actql-local-runtime')}
    if any(value != options.version for value in versions.values()):
        raise RuntimeError('Check acceptance requires one original release cohort')

    completed: list[str] = []
    reports: list[dict] = []
    client = None
    try:
        client = actql.open(state_dir=options.state_dir)
        completed.append('public open new installation')
        text = 'SELECT 29 AS id'
        bound = client.check(text, kind='text', format='sql', scope='bound_input')
        if (bound.outcome != 'completed' or bound.report is None
                or bound.report.verdict != 'verified'):
            raise AssertionError('Original bound constant query was not verified')
        original = actql.get_check_input(bound, 'source')
        if original is None or original['text'] != text:
            raise AssertionError('Original Check source snapshot is unavailable')
        reports.append(bound.to_dict())
        completed.append('public bound Check and original source snapshot')

        repeated = client.check(text, kind='text', format='sql', scope='bound_input')
        if (repeated.outcome != 'completed' or repeated.report is None
                or repeated.report.verdict != 'verified'
                or repeated.report.context_ref != bound.report.context_ref
                or repeated.report.inputs != bound.report.inputs):
            raise AssertionError('Unchanged original Check context/input binding changed')
        reports.append(repeated.to_dict())
        completed.append('same original context and input on another admitted Check')

        template = client.check(text, kind='text', format='sql', scope='template_only')
        if (template.outcome != 'completed' or template.report is None
                or template.report.verdict != 'verified'
                or template.report.scope['kind'] != 'template_only'
                or template.report.context_ref == bound.report.context_ref
                or template.report.inputs != bound.report.inputs):
            raise AssertionError('Requested Check scope lost its distinct context binding')
        reports.append(template.to_dict())
        completed.append('public template-only Check with distinct scope context')

        invalid = client.check('SELECT !', kind='text', format='sql', scope='bound_input')
        if (invalid.outcome != 'completed' or invalid.report is None
                or invalid.report.verdict != 'invalid'):
            raise AssertionError('Authored syntax rejection was not observed from Common')
        reports.append(invalid.to_dict())
        completed.append('public invalid syntax report')
        client.close()
        completed.append('explicit public close')
    except BaseException as failure:
        # Only the same original Client may discharge its own pending cleanup.
        # Propagate a failed close; process exit is not its acknowledgment.
        if client is not None:
            try:
                client.close()
            except BaseException as cleanup:
                raise BaseExceptionGroup(
                    'Original Check failure and pending cleanup', [failure, cleanup]) from None
        raise

    result = {'passed': True, 'publicChecks': 4, 'completed': completed,
              'pid': os.getpid(), 'versions': versions, 'reports': reports,
              'sourceOverlay': False, 'newSubmission': False,
              'qualification': 'Normal installed Local Check only; no Run execution'}
    options.result.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'stage': 'closed', 'pid': os.getpid(), 'publicChecks': 4}), flush=True)
    if options.await_close_observation:
        # An external observer may check live original descriptors. This input
        # only keeps the process observable; it issues no resource/close ACK.
        if sys.stdin.readline().strip() != 'observed':
            raise RuntimeError('Original close observer did not complete')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
