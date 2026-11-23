"""Diagnostic interruption of a fresh saved read through the installed facade.

The caller supplies a new fixture's successful warm reference and its current
normal wheel installation. This is not a pristine default-fuel success case:
the test wraps the Saved call and its physical current ports to reduce remaining fuel to zero
inside the actual saved-binding validation's original current callback. It
does not replace the Core, module, physical current result, or cleanup callback.
The same instance must retain its physical duties and close explicitly.
"""
from pathlib import Path
from importlib import metadata
import json
import os
from runpy import run_path
import sys
import time
import traceback


def causes(error):
    seen = set()
    while error is not None and id(error) not in seen and len(seen) < 24:
        seen.add(id(error))
        yield error
        error = getattr(error, 'original_error', None) or error.__cause__ or error.__context__


def error_chain(error):
    return [{
        'type': type(cause).__name__, 'module': type(cause).__module__,
        'code': getattr(cause, 'code', None), 'message': str(cause),
        'frames': [{'file': frame.filename, 'line': frame.lineno, 'name': frame.name}
                   for frame in traceback.extract_tb(cause.__traceback__)],
    } for cause in causes(error)]


def main():
    if len(sys.argv) != 3 and not (len(sys.argv) == 4 and sys.argv[3] == '--without-fd-observer'):
        raise ValueError('Select the fresh fixture directory and exact wheel Source')
    fd_observer = len(sys.argv) == 3
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
    from actql_sdk._local_core import LocalCore, _Output
    from actql_sdk._local_distribution import installed_local_components
    from wasmtime import Trap
    fuel_trap_code = None
    if not fd_observer:
        fuel_trap_code = run_path(str(Path(__file__).with_name('ci-python-installed-fuel.py')))['fuel_trap_code']
    if not Path(actql.__file__).is_relative_to(Path(sys.prefix)):
        raise ValueError('Installed public facade required; no source overlay')
    installed = installed_local_components()
    if installed.source_sha != source:
        raise ValueError('Foreign installed Saved interruption source')
    report.update(module=installed.module_sha256, image=installed.image_sha256)
    report['versions'] = {name: metadata.version(name)
                          for name in ('actql', 'actql-sdk', 'actql-local-runtime', 'wasmtime')}
    call, current, current_operation = LocalCore._call, LocalCore._journal_current, LocalCore._journal_current_operation
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
                and name == 'validate_payload_binding' and len(arguments) == 5
                and arguments[0] > 0 and arguments[1] > 0):
            # The preceding zero-loan capability query never enters this
            # selection. The input must be the live original Saved parent.
            selected[0] = False
            if entered[0] or held:
                raise AssertionError('The same selected invocation must not repeat')
            source, = [loan for loan in self._loans.values() if type(loan) is _Output
                       and loan.handle == arguments[0] and loan.family == 'submission_lookup']
            self._owned_output(source, 'submission_lookup')
            scope = self._host_operation_scope
            if not self._ordinary_host or self._host_fuel_phase != 'operation' or scope is None:
                raise AssertionError('Original normal outer operation required')
            held.append((self, self._store, scope, self._host_operation_id))
            entered[0] = True
            try:
                return call(self, family, name, *arguments)
            finally:
                entered[0] = False
        return call(self, family, name, *arguments)

    def interrupt(self, ticket, result, *, operation_import):
        if not entered[0] or ticket <= 0 or report['injections']:
            return result
        original, store, scope, operation = held[0]
        expected = operation if operation_import else 0
        if result != expected:
            return result
        if self is not original or self._store is not store:
            raise AssertionError('Foreign Core or replacement Store')
        if (not self._invoking or self._host_fuel_phase != 'operation'
                or self._host_operation_scope is not scope or self._host_operation_id != operation):
            raise AssertionError('Original saved binding is not in flight in the same operation')
        before = store.get_fuel()
        if before <= 0:
            raise AssertionError('Counter must reduce an available original budget')
        store.set_fuel(0)
        report['injections'].append({'before': before, 'after': store.get_fuel(),
                                     'actualCurrentResult': result, 'ticket': ticket,
                                     'operationImport': operation_import, 'operation': operation})
        return result

    def observed_current(self, ticket):
        return interrupt(self, ticket, current(self, ticket), operation_import=False)

    def observed_current_operation(self, ticket):
        result = current_operation(self, ticket)
        return interrupt(self, ticket, result, operation_import=True)

    client, close_attempted = None, False
    LocalCore._call = observed_call
    LocalCore._journal_current = observed_current
    LocalCore._journal_current_operation = observed_current_operation
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
            if fuel_trap_code is not None:
                trap, = [cause for cause in causes(error) if type(cause) is Trap]
                report['originalTrapCode'] = fuel_trap_code(trap)
        else:
            raise AssertionError('Selected interruption did not fail the operation')
        if len(held) != 1 or len(report['injections']) != 1:
            raise AssertionError('The exact selected original was not interrupted once')
        if not any('all fuel consumed by WebAssembly' in e['message']
                   for e in report['expectedOperationFailure']):
            raise AssertionError('Expected actual Wasm instruction exhaustion')
        core, store, _, _ = held[0]
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
        if fd_observer:
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
        if fd_observer:
            time.sleep(2)
        event('same original explicit cleanup completed')
        report.update(passed=True, cases=1, normalFenced=True, sameStore=True, firstClose=True)
    except BaseException as error:
        report['failure'] = error_chain(error)
    finally:
        if client is not None and not close_attempted:
            try:
                close_attempted = True
                client.close()
            except BaseException as error:
                report['cleanupFailure'] = error_chain(error)
        LocalCore._call = call
        LocalCore._journal_current = current
        LocalCore._journal_current_operation = current_operation
        (directory / 'fresh-interruption-result.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
