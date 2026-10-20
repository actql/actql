"""Diagnostic interruption of a fresh saved read through the installed facade.

The caller supplies a new fixture's successful warm reference and its current
normal wheel installation. This is not a pristine default-fuel success case:
the test wraps two private call ports solely to reduce remaining fuel to zero
inside the actual saved-binding validation's original current callback. It
does not replace the Core, module, physical current result, or cleanup callback.
The same instance must retain its physical duties and close explicitly.
"""
from pathlib import Path
from importlib import metadata
import json
import os
import sys
import time
import traceback


def error_chain(error):
    result, seen = [], set()
    while error is not None and id(error) not in seen and len(result) < 24:
        seen.add(id(error))
        result.append({
            'type': type(error).__name__, 'module': type(error).__module__,
            'code': getattr(error, 'code', None), 'message': str(error),
            'frames': [{'file': frame.filename, 'line': frame.lineno, 'name': frame.name}
                       for frame in traceback.extract_tb(error.__traceback__)],
        })
        error = getattr(error, 'original_error', None) or error.__cause__ or error.__context__
    return result


def main():
    if len(sys.argv) != 3:
        raise ValueError('Select the fresh fixture directory and exact wheel Source')
    directory = Path(sys.argv[1]).resolve()
    source = sys.argv[2]
    if len(source) != 40 or any(ch not in '0123456789abcdef' for ch in source):
        raise ValueError('Exact wheel Source required')
    original = json.loads((directory / 'fresh-original-reference.json').read_text())
    state = directory / 'fresh-public-state' / '.actql'
    if original['stateDir'] != str(state) or original['warmPID'] == os.getpid():
        raise ValueError('Different-process original warm fixture required')
    if not state.is_dir():
        raise ValueError('Fresh original installation is missing')
    report = {
        'source': source, 'pid': os.getpid(), 'passed': False, 'cases': 0,
        'qualification': 'Injected instruction interruption of the actual normal image; not default-fuel acceptance',
        'newSubmission': False, 'installedSourceOverlay': False,
        'runtimeCallInstrumentation': True, 'injections': [], 'cleanupEntrances': [],
    }
    events = directory / 'interruption-stages.jsonl'

    def event(name):
        row = {'name': name, 'time': time.time(), 'monotonic': time.monotonic(), 'pid': os.getpid()}
        with events.open('a') as output:
            output.write(json.dumps(row) + '\n')
        print(json.dumps({'stage': row}), flush=True)

    import actql
    from actql_sdk._local_core import LocalCore
    if not Path(actql.__file__).is_relative_to(Path(sys.prefix)):
        raise ValueError('Installed public facade required; no source overlay')
    report['versions'] = {name: metadata.version(name)
                          for name in ('actql', 'actql-sdk', 'actql-local-runtime', 'wasmtime')}
    call, current = LocalCore._call, LocalCore._journal_current
    selected, entered, held = [False], [False], []

    def observed_call(self, family, name, *arguments):
        if family == 'submission' and name == 'begin_cleanup':
            report['cleanupEntrances'].append({
                'sameCore': bool(held) and self is held[0][0],
                'sameStore': bool(held) and self._store is held[0][1],
                'invoking': self._invoking, 'phase': self._host_fuel_phase,
                'closing': self._closing,
            })
        if (selected[0] and family == 'publication_commit_export'
                and name == 'validate_payload_binding'):
            selected[0] = False
            if entered[0] or held:
                raise AssertionError('The same selected invocation must not repeat')
            held.append((self, self._store))
            if not self._ordinary_host or self._host_fuel_phase != 'operation':
                raise AssertionError('Original normal outer operation required')
            entered[0] = True
            try:
                return call(self, family, name, *arguments)
            finally:
                entered[0] = False
        return call(self, family, name, *arguments)

    def observed_current(self, ticket):
        result = current(self, ticket)
        if entered[0] and result == 0 and not report['injections']:
            if not held or self is not held[0][0] or self._store is not held[0][1]:
                raise AssertionError('Foreign Core or replacement Store')
            if not self._invoking or self._host_fuel_phase != 'operation':
                raise AssertionError('Original saved binding is not in flight')
            before = self._store.get_fuel()
            if before <= 0:
                raise AssertionError('Counter must reduce an available original budget')
            self._store.set_fuel(0)
            report['injections'].append({'before': before, 'after': self._store.get_fuel(),
                                         'actualCurrentResult': result, 'ticket': ticket})
        return result

    client, close_attempted = None, False
    LocalCore._call, LocalCore._journal_current = observed_call, observed_current
    try:
        event('public reopen original fresh installation')
        client = actql.open(state_dir=state)
        event('public attach exact saved original Run')
        execution = client.attach(original['reference'])
        if dict(execution.ref) != original['reference']:
            raise AssertionError('Saved reference changed')
        selected[0] = True
        event('public saved Result read with selected diagnostic interruption')
        try:
            execution.result(original['resultName']).all()
        except BaseException as error:
            report['expectedOperationFailure'] = error_chain(error)
        else:
            raise AssertionError('Selected interruption did not fail the operation')
        if len(held) != 1 or len(report['injections']) != 1:
            raise AssertionError('The exact selected original was not interrupted once')
        if not any('all fuel consumed by WebAssembly' in e['message']
                   for e in report['expectedOperationFailure']):
            raise AssertionError('Expected actual Wasm instruction exhaustion')
        core, store = held[0]
        if not core._closing or core._invoking or core._store is not store or store.get_fuel() != 0:
            raise AssertionError('Interrupted original did not remain fenced and quiescent')
        try:
            with core._host_operation():
                raise AssertionError('Exhausted normal operation revived')
        except RuntimeError as refusal:
            report['normalEntryRefusal'] = str(refusal)
        event('original interrupted physical custody retained before explicit cleanup')
        print('E_SAVED_INTERRUPTED:' + json.dumps({'pid': os.getpid(), 'stateDir': str(state)}),
              file=sys.stderr, flush=True)
        # Permit the independent observer to inspect the live original FDs.
        time.sleep(2)
        event('explicit public close of same interrupted original')
        close_attempted = True
        client.close()
        if not core._closed or not core._retired or core._store is not None:
            raise AssertionError('Actual original Core retirement is unconfirmed')
        if not report['cleanupEntrances'] or any(not entry['sameCore'] or not entry['sameStore']
                or entry['invoking'] or entry['phase'] != 'cleanup' or not entry['closing']
                for entry in report['cleanupEntrances']):
            raise AssertionError('Missing same-original cleanup entrance after unwind')
        print('E_SAVED_CLOSED:' + json.dumps({'pid': os.getpid(), 'stateDir': str(state),
                                           'phase': 'interrupted'}), file=sys.stderr, flush=True)
        time.sleep(2)
        event('same original explicit cleanup completed')
        report.update(passed=True, cases=1)
    except BaseException as error:
        report['failure'] = error_chain(error)
    finally:
        if client is not None and not close_attempted:
            try:
                close_attempted = True
                client.close()
            except BaseException as error:
                report['cleanupFailure'] = error_chain(error)
        LocalCore._call, LocalCore._journal_current = call, current
        (directory / 'fresh-interruption-result.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
