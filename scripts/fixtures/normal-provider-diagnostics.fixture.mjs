// Bounded caller-owned diagnostics only. No Host/Core handle, reader, grant,
// retry or failure classification is issued by this fixture helper.
export function normalProviderDiagnostics({phase, work, write}) {
  const terminals = [], requests = [], failures = [];
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
      await put('normal-diagnostic-before-assert.json', {phase, terminals, http: {calls, requests}, work: snapshot()}, false);
    },
    async finish(firstClose, fd, cleanup) {
      const value = {phase, qualification: 'Instrumented caller diagnostics, not pristine timing or an internal physical ACK',
        terminals, http: {calls, requests}, work: snapshot(), firstClose, fd, cleanup, diagnosticFailures: failures};
      await put('normal-diagnostic.json', value, false);
      return {value, complete: failures.length === 0 && value.work.complete === true};
    },
  };
}
