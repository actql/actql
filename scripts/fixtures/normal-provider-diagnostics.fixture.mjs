// Bounded caller-owned diagnostics only. No Host/Core handle, reader, grant,
// retry or failure classification is issued by this fixture helper.
import {types as nodeTypes} from 'node:util';

function ownData(value, key) {
  if (value === null || typeof value !== 'object' || nodeTypes.isProxy(value)) return undefined;
  const field = Object.getOwnPropertyDescriptor(value, key);
  return field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
}

// Copy only existing inert diagnostic scalars. In particular, a code-site
// message, exception, cause object or arbitrary diagnostic member is not read.
function diagnosticScalars(value, cleanup = false) {
  const data = {};
  const accept = (key, valid) => {
    const selected = ownData(value, key);
    if (valid(selected)) data[key] = selected;
  };
  if (cleanup) {
    accept('owner', v => ['local_managed', 'managed_operations'].includes(v));
    accept('phase', v => ['close_additional', 'close_operations', 'await_stop', 'settle_operations', 'refresh_cleanup'].includes(v));
    accept('continuation', v => ['runnable', 'blocked', 'unavailable'].includes(v));
  } else {
    accept('code', v => typeof v === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,95}$/u.test(v));
    for (const key of ['phase', 'kind', 'cause']) {
      accept(key, v => typeof v === 'string' && v.length <= 96 && /^[a-z_]+(?:\.[a-z_]+)*$/u.test(v));
    }
    for (const key of ['task', 'unit', 'step', 'controlWorkLimit']) {
      accept(key, v => Number.isSafeInteger(v) && v >= 0 && v <= 2147483647);
    }
    accept('workLimit', v => Number.isSafeInteger(v) && v >= 0 && v <= 2147483647 ||
      typeof v === 'string' && /^(?:0|[1-9][0-9]{0,18})$/u.test(v) && BigInt(v) <= 9223372036854775807n);
    accept('dimension', v => ['retained_bytes', 'execution_bytes'].includes(v));
    accept('setting', v => ['installation.sourceFreeMaxWork', 'unavailable'].includes(v));
  }
  return Object.keys(data).length === 0 ? undefined : data;
}

export function normalProviderDiagnostics({phase, work, write}) {
  const terminals = [], requests = [], failures = [], dispatchFailures = [];
  let calls = 0;
  const problem = cause => ({name: typeof cause?.name === 'string' ? cause.name : null,
    code: typeof cause?.code === 'string' ? cause.code : null});
  const note = cause => {if (failures.length < 8) failures.push(problem(cause));};
  const put = async (path, value, exclusive) => {
    try {
      const wire = JSON.stringify(value) + '\n';
      if (Buffer.byteLength(wire) > 1048576) throw Error('NormalDiagnosticByteLimit');
      await write(path, wire, {mode: 0o600, ...(exclusive ? {flag: 'wx'} : {})});
    } catch (cause) {note(cause);}
  };
  const snapshot = () => {
    try {return work.snapshot();}
    catch (cause) {note(cause);return {complete: false, unavailable: true};}
  };
  return {
    dispatchFailure(event, detail) {
      if (event !== 'dispatch_failed') return;
      if (dispatchFailures.length === 2) {note(Error('NormalDiagnosticDispatchLimit'));return;}
      try {
        const record = {};
        const primary = diagnosticScalars(ownData(detail, 'primaryDiagnostic'));
        const cleanup = diagnosticScalars(ownData(detail, 'cleanupDiagnostic'), true);
        if (primary !== undefined) record.primary = primary;
        if (cleanup !== undefined) record.cleanup = cleanup;
        for (const key of ['issueTag', 'nestedIssueTag', 'leafIssueTag']) {
          const value = ownData(detail, key);
          if (Number.isSafeInteger(value) && value >= 0 && value <= 65535) record[key] = value;
        }
        dispatchFailures.push(record);
      } catch {note(Error('NormalDiagnosticDispatchProjectionFailed'));}
    },
    request(request) {
      calls++;
      if (requests.length === 2) {note(Error('NormalDiagnosticRequestLimit'));return;}
      const method = typeof request.method === 'string' && /^[A-Z]{1,16}$/u.test(request.method) ? request.method : '<unexpected>';
      // A single selected fixture endpoint. Never copy headers/body/query or
      // disclose an arbitrary unexpected URL supplied by a different caller.
      const path = request.url?.split('?')[0] === '/v1/chat/completions' ? '/v1/chat/completions' : '<unexpected>';
      requests.push({method, path});
    },
    async terminal(index, value) {
      if (![0, 1].includes(index) || terminals.some(entry => entry.index === index)) {
        note(Error('NormalDiagnosticTerminalConflict'));return;
      }
      const path = `terminal-${index}.json`;
      terminals.push({index, path});
      // Preserve the FULL original public reply before its existing assertion.
      // It is not another status call or a recovered/reconstructed terminal.
      await put(path, value, true);
      await put('normal-diagnostic-before-assert.json', {phase, terminals, dispatchFailures, http: {calls, requests}, work: snapshot()}, false);
    },
    async finish(firstClose, fd, cleanup) {
      const value = {phase, qualification: 'Instrumented caller diagnostics, not pristine timing or an internal physical ACK',
        terminals, dispatchFailures, http: {calls, requests}, work: snapshot(), firstClose, fd, cleanup, diagnosticFailures: failures};
      await put('normal-diagnostic.json', value, false);
      return {value, complete: failures.length === 0 && value.work.complete === true};
    },
  };
}
