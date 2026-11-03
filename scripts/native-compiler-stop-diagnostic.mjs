// Failure-only observation of one original compiler command, not a test runner.
import {spawnSync} from 'node:child_process';
import {mkdtempSync} from 'node:fs';
import {join} from 'node:path';

export function failedCoreDriver(root, moonHome) {
  const tool = join(moonHome, 'bin', 'moon');
  const args = ['generate-test-driver', '--output-driver',
    join(root, '_build/native/debug/test/__generated_driver_for_blackbox_test.mbt'),
    '--output-metadata', join(root, '_build/native/debug/test/__blackbox_test_info.json'),
    join(root, 'src/environment_test.mbt'), '--target', 'native', '--pkg-name',
    'actql/actql', '--driver-kind', 'blackbox'];
  const expected = 'failed: ' + [tool, ...args].join(' ');
  const pending = {stdout: '', stderr: ''};
  let observed = false;
  return {tool, args: Object.freeze(args), get observed() { return observed; },
    write(chunk, stream = 'stderr') {
      if (!(stream in pending)) return;
      const parts = (pending[stream] + chunk.toString()).split('\n');
      pending[stream] = parts.pop();
      for (const line of parts) if (line.replace(/\r$/u, '') === expected) observed = true;
      if (pending[stream].length > 16384) pending[stream] = '';
    }};
}

// LLDB launches asynchronously so this Python loop can enforce its own bound
// and kill the same diagnostic inferior before the debugger exits.
const debuggerProgram = `import lldb, json, base64, time, re
target = lldb.debugger.GetSelectedTarget()
lldb.debugger.SetAsync(True)
info = target.GetLaunchInfo()
info.SetEnvironmentEntries(json.loads(base64.b64decode("ENVIRONMENT")), False)
info.SetWorkingDirectory(json.loads(base64.b64decode("DIRECTORY")))
flags = info.GetLaunchFlags()
flags &= ~lldb.eLaunchFlagDisableASLR
flags &= ~lldb.eLaunchFlagStopAtEntry
info.SetLaunchFlags(flags)
info.SetDetachOnError(False)
info.AddSuppressFileAction(1, False, True)
info.AddSuppressFileAction(2, False, True)
error = lldb.SBError()
process = target.Launch(info, error)
result = {"attempted": True, "frames": [], "cause": "unobserved", "cleanup": "unobserved"}
deadline = time.monotonic() + 52
terminal = (lldb.eStateStopped, lldb.eStateCrashed, lldb.eStateExited, lldb.eStateDetached, lldb.eStateInvalid)
while process.IsValid() and process.GetState() not in terminal and time.monotonic() < deadline:
    time.sleep(0.05)
if process.IsValid() and process.GetState() in (lldb.eStateStopped, lldb.eStateCrashed):
    thread = process.GetSelectedThread()
    reason = thread.GetStopDescription(256) or ""
    selected = re.search(r"EXC_[A-Z_]+|SIG[A-Z0-9]+", reason)
    if selected:
        result["cause"] = selected.group(0)
    for index in range(16):
        frame = thread.GetFrameAtIndex(index)
        if not frame.IsValid():
            break
        module = frame.GetModule().GetFileSpec().GetFilename() or ""
        symbol = frame.GetFunctionName() or frame.GetSymbol().GetName() or ""
        if (0 < len(module) <= 128 and 0 < len(symbol) <= 256 and
            re.fullmatch(r"[A-Za-z0-9_.+-]+", module) and
            re.fullmatch(r"[A-Za-z0-9_:$<>~.,()*\\[\\] +/=-]+", symbol)):
            result["frames"].append({"module": module, "symbol": symbol})
if process.IsValid() and process.GetState() not in (lldb.eStateExited, lldb.eStateDetached, lldb.eStateInvalid):
    killed = process.Kill()
    deadline = time.monotonic() + 4
    while killed.Success() and process.GetState() != lldb.eStateExited and time.monotonic() < deadline:
        time.sleep(0.05)
    result["cleanup"] = "exited" if process.GetState() == lldb.eStateExited else "unconfirmed"
elif process.IsValid() and process.GetState() == lldb.eStateExited:
    result["cleanup"] = "exited"
print("ACTQL_COMPILER_STOP " + json.dumps(result))
`;

export function diagnoseFailedCoreDriver({driver, root, namespace, env}, run = spawnSync) {
  if (!driver.observed) return {attempted: false, cause: 'original-failure-not-observed'};
  const output = mkdtempSync(join(namespace, 'compiler-stop-'));
  const args = [...driver.args];
  args[2] = join(output, 'blackbox-driver.mbt');
  args[4] = join(output, 'blackbox-metadata.json');
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64');
  const program = debuggerProgram
    .replace('ENVIRONMENT', encode(Object.entries(env).filter(([, value]) => value !== undefined)
      .map(([key, value]) => `${key}=${value}`)))
    .replace('DIRECTORY', encode(root));
  const input = 'script exec(' + JSON.stringify(program) + ')\nquit\n';
  const debuggerEnv = {...env};
  delete debuggerEnv.DYLD_INSERT_LIBRARIES;
  delete debuggerEnv.LD_PRELOAD;
  const result = run('xcrun', ['lldb', '--batch', '--no-lldbinit', '--source-quietly', '--source',
    '/dev/stdin', '--', driver.tool, ...args], {cwd: root, env: debuggerEnv,
    input, encoding: 'utf8', timeout: 60000, killSignal: 'SIGKILL', maxBuffer: 1048576});
  let selected;
  for (const line of (result.stdout ?? '').split('\n')) {
    if (!line.startsWith('ACTQL_COMPILER_STOP ') || line.length > 16384) continue;
    try {
      const value = JSON.parse(line.slice('ACTQL_COMPILER_STOP '.length));
      if (value.attempted === true && Array.isArray(value.frames) && value.frames.length <= 16 &&
          /^(?:unobserved|EXC_[A-Z_]+|SIG[A-Z0-9]+)$/u.test(value.cause) &&
          ['unobserved', 'unconfirmed', 'exited'].includes(value.cleanup)) {
        selected = {attempted: true, cause: value.cause, cleanup: value.cleanup,
          frames: value.frames.filter(frame => typeof frame.module === 'string' &&
            /^[A-Za-z0-9_.+-]{1,128}$/u.test(frame.module) && typeof frame.symbol === 'string' &&
            /^[A-Za-z0-9_:$<>~.,()*\[\] +/=-]{1,256}$/u.test(frame.symbol))
            .map(({module, symbol}) => ({module, symbol}))};
      }
    } catch { /* A malformed debugger result is not a compiler diagnosis. */ }
  }
  return {...(selected ?? {attempted: true, cause: 'unobserved', cleanup: 'unobserved', frames: []}),
    debuggerStatus: result.status, debuggerSignal: result.signal,
    timedOut: result.error?.code === 'ETIMEDOUT', relocatedOutputOperands: [2, 4]};
}
