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
const debuggerProgram = `import lldb, json, base64, time, re, os
target = lldb.debugger.GetSelectedTarget()
lldb.debugger.SetAsync(True)
info = target.GetLaunchInfo()
command = json.loads(base64.b64decode("COMMAND"))
info.SetArguments(command, False)
info.SetExecutableFile(lldb.SBFileSpec(command[0]), False)
def image_path(spec):
    return os.path.join(spec.GetDirectory() or "", spec.GetFilename() or "")
arguments_match = [info.GetArgumentAtIndex(i) for i in range(info.GetNumArguments())] == command
image_match = image_path(target.GetExecutable()) == command[0] and image_path(info.GetExecutableFile()) == command[0]
info.SetEnvironmentEntries(json.loads(base64.b64decode("ENVIRONMENT")), False)
expected_environment = dict(entry.split("=", 1) for entry in json.loads(base64.b64decode("OBSERVATION_ENVIRONMENT")))
environment_keys = ("DYLD_INSERT_LIBRARIES", "LD_PRELOAD", "ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT")
launch_environment = dict(info.GetEnvironmentEntryAtIndex(i).split("=", 1) for i in range(info.GetNumEnvironmentEntries()))
launch_environment_matches = {key: launch_environment.get(key) == expected_environment.get(key) for key in environment_keys}
info.SetWorkingDirectory(json.loads(base64.b64decode("DIRECTORY")))
flags = info.GetLaunchFlags()
flags &= ~lldb.eLaunchFlagDisableASLR
flags &= ~lldb.eLaunchFlagStopAtEntry
info.SetLaunchFlags(flags)
info.SetDetachOnError(False)
info.AddSuppressFileAction(1, False, True)
info.AddSuppressFileAction(2, False, True)
error = lldb.SBError()
launch_matches = arguments_match and image_match and all(launch_environment_matches.values())
process = target.Launch(info, error) if launch_matches else lldb.SBProcess()
result = {"attempted": True, "frames": [], "cause": "unobserved", "cleanup": "unobserved",
          "launchArgumentsMatch": arguments_match, "launchImageMatch": image_match,
          "launchSucceeded": launch_matches and error.Success() and process.IsValid(),
          "launchEnvironmentMatches": launch_environment_matches,
          "targetEnvironmentMatches": {key: None for key in environment_keys}, "readerLibraryLoaded": None,
          "inferiorExitStatus": None, "terminatedByDiagnostic": False}
def observe_reader_image():
    # A true value requires an actually loaded target image. A missed short
    # process or an unavailable module list remains unobserved, not absent.
    expected = expected_environment.get("DYLD_INSERT_LIBRARIES") or expected_environment.get("LD_PRELOAD")
    if not expected or not process.IsValid() or process.GetState() == lldb.eStateExited:
        return
    try:
        for index in range(target.GetNumModules()):
            module = target.GetModuleAtIndex(index)
            if target.IsLoaded(module) and os.path.realpath(image_path(module.GetFileSpec())) == os.path.realpath(expected):
                result["readerLibraryLoaded"] = True
    except Exception:
        pass
deadline = time.monotonic() + 52
terminal = (lldb.eStateStopped, lldb.eStateCrashed, lldb.eStateExited, lldb.eStateDetached, lldb.eStateInvalid)
while process.IsValid() and process.GetState() not in terminal and time.monotonic() < deadline:
    observe_reader_image()
    time.sleep(0.05)
if process.IsValid() and process.GetState() in (lldb.eStateStopped, lldb.eStateCrashed):
    observe_reader_image()
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
    # Read only equality bits for fixed keys from this stopped inferior. Do
    # this after saving the original stop and frames; never print values or
    # expression errors. Exited inferiors have no target readback evidence.
    for key in environment_keys:
        try:
            value = expected_environment.get(key)
            predicate = "value == 0" if value is None else "value != 0 && strcmp(value, " + json.dumps(value) + ") == 0"
            expression = "({ extern char *getenv(const char *); extern int strcmp(const char *, const char *); const char *value = getenv(" + json.dumps(key) + "); " + predicate + "; })"
            options = lldb.SBExpressionOptions()
            options.SetTimeoutInMicroSeconds(1000000)
            options.SetIgnoreBreakpoints(True)
            options.SetUnwindOnError(True)
            options.SetLanguage(lldb.eLanguageTypeC)
            observed = target.EvaluateExpression(expression, options)
            if observed.IsValid() and observed.GetError().Success():
                result["targetEnvironmentMatches"][key] = observed.GetValueAsUnsigned() == 1
        except Exception:
            pass
if process.IsValid() and process.GetState() not in (lldb.eStateExited, lldb.eStateDetached, lldb.eStateInvalid):
    result["terminatedByDiagnostic"] = True
    killed = process.Kill()
    deadline = time.monotonic() + 4
    while killed.Success() and process.GetState() != lldb.eStateExited and time.monotonic() < deadline:
        time.sleep(0.05)
    result["cleanup"] = "exited" if process.GetState() == lldb.eStateExited else "unconfirmed"
elif process.IsValid() and process.GetState() == lldb.eStateExited:
    result["cleanup"] = "exited"
    result["inferiorExitStatus"] = process.GetExitStatus()
print("ACTQL_COMPILER_STOP " + json.dumps(result))
`;

export function diagnoseFailedCoreDriver({driver, root, namespace, env}, run = spawnSync) {
  if (!driver.observed) return {attempted: false, cause: 'original-failure-not-observed'};
  const output = mkdtempSync(join(namespace, 'compiler-stop-'));
  const args = [...driver.args];
  args[2] = join(output, 'blackbox-driver.mbt');
  args[4] = join(output, 'blackbox-metadata.json');
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64');
  const entries = Object.entries(env).filter(([, value]) => value !== undefined)
    .map(([key, value]) => `${key}=${value}`);
  const program = debuggerProgram
    .replace('COMMAND', encode([driver.tool, ...args]))
    .replace('ENVIRONMENT', encode(entries))
    .replace('OBSERVATION_ENVIRONMENT', encode(entries))
    .replace('DIRECTORY', encode(root));
  const input = 'script exec(' + JSON.stringify(program) + ')\nquit\n';
  const debuggerEnv = {...env};
  delete debuggerEnv.DYLD_INSERT_LIBRARIES;
  delete debuggerEnv.LD_PRELOAD;
  // One failure-only serial control uses the same image, inputs and original
  // environment outside LLDB. Its separate fresh outputs cannot supply tests.
  const serialArgs = [...args];
  serialArgs[2] = join(output, 'serial-driver.mbt');
  serialArgs[4] = join(output, 'serial-metadata.json');
  const serial = run(driver.tool, serialArgs, {cwd: root, env, stdio: 'ignore',
    timeout: 15000, killSignal: 'SIGKILL'});
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
          launchArgumentsMatch: value.launchArgumentsMatch === true,
          launchImageMatch: value.launchImageMatch === true,
          launchSucceeded: value.launchSucceeded === true,
          ...Object.fromEntries(['launchEnvironmentMatches', 'targetEnvironmentMatches'].map(field =>
            [field, Object.fromEntries(['DYLD_INSERT_LIBRARIES', 'LD_PRELOAD',
              'ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT'].map(key =>
              [key, typeof value[field]?.[key] === 'boolean' ? value[field][key] : null]))])),
          readerLibraryLoaded: value.readerLibraryLoaded === true ? true : null,
          inferiorExitStatus: Number.isInteger(value.inferiorExitStatus) &&
            value.terminatedByDiagnostic === false ? value.inferiorExitStatus : null,
          terminatedByDiagnostic: value.terminatedByDiagnostic === true,
          frames: value.frames.filter(frame => typeof frame.module === 'string' &&
            /^[A-Za-z0-9_.+-]{1,128}$/u.test(frame.module) && typeof frame.symbol === 'string' &&
            /^[A-Za-z0-9_:$<>~.,()*\[\] +/=-]{1,256}$/u.test(frame.symbol))
            .map(({module, symbol}) => ({module, symbol}))};
      }
    } catch { /* A malformed debugger result is not a compiler diagnosis. */ }
  }
  return {...(selected ?? {attempted: true, cause: 'unobserved', cleanup: 'unobserved', frames: []}),
    serial: {attempted: true,
      exitStatus: Number.isInteger(serial.status) && serial.error?.code !== 'ETIMEDOUT' ? serial.status : null,
      signal: /^SIG[A-Z0-9]+$/u.test(serial.signal ?? '') ? serial.signal : null,
      timedOut: serial.error?.code === 'ETIMEDOUT',
      errorCode: ['ENOENT', 'EACCES', 'EPERM', 'ETIMEDOUT', 'ENOBUFS'].includes(serial.error?.code)
        ? serial.error.code : null},
    debuggerStatus: result.status, debuggerSignal: result.signal,
    timedOut: result.error?.code === 'ETIMEDOUT', relocatedOutputOperands: [2, 4]};
}
