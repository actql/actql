import assert from 'node:assert/strict';
// Private installer preparation. Creating project files does not initialize a
// Host, issue a key, adopt configuration or report a runnable mock installation.
import {constants, closeSync, fstatSync, lstatSync, mkdirSync, openSync,
  opendirSync, realpathSync, writeSync, fsyncSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {projectTemplateFiles} from './project-template.mjs';

const fail = (code, message) => { throw Object.assign(new Error(message), {code}); };
const same = (a, b) => a.dev === b.dev && a.ino === b.ino;
const emptyDirectory = path => {
  const directory = opendirSync(path);
  let failed = false, cause;
  try { return directory.readSync() === null; }
  catch (error) { failed = true; cause = error; throw error; }
  finally {
    try { directory.closeSync(); }
    catch (cleanupCause) { throw Object.assign(new Error('Project directory cleanup is unconfirmed.', {
      cause: failed ? cause : cleanupCause,
    }), {
      code: 'ACTQL_E_PROJECT_CLEANUP_PENDING', directory, cleanupCause,
    }); }
  }
};

// Each write is exclusive. A failed or interrupted preparation is retained for
// inspection; retry cannot overwrite the partial project or any existing state.
export function scaffoldProject(directory, template) {
  const files = projectTemplateFiles(template);
  if (typeof directory !== 'string' || directory.length === 0 || directory.length > 4096 ||
      directory.includes('\0')) {
    fail('ACTQL_E_PROJECT_PATH', 'A project directory is required.');
  }
  const requested = resolve(directory);
  const parent = realpathSync(dirname(requested));
  const root = join(parent, basename(requested));
  if (root === parent) fail('ACTQL_E_PROJECT_PATH', 'A project directory is required.');
  try { mkdirSync(root, {mode: 0o755}); }
  catch (error) { if (error.code !== 'EEXIST') throw error; }
  const original = lstatSync(root);
  if (!original.isDirectory() || original.isSymbolicLink() || original.uid !== process.getuid() ||
      (original.mode & 0o022) !== 0 || !emptyDirectory(root)) {
    fail('ACTQL_E_PROJECT_EXISTS', 'The project directory must be an empty owned directory.');
  }
  const checkRoot = () => {
    const current = lstatSync(root);
    if (!current.isDirectory() || current.isSymbolicLink() || !same(original, current)) {
      fail('ACTQL_E_PROJECT_CHANGED', 'The project directory changed during preparation.');
    }
  };
  checkRoot();
  // The existing installation Owner must create state with its exclusive
  // directory witness. Even an empty precreated .actql would lose that custody.
  const directories = new Map([['', original]]);
  const created = [];
  for (const [name, text] of Object.entries(files)) {
    checkRoot();
    const subdirectory = dirname(name) === '.' ? '' : dirname(name);
    if (!directories.has(subdirectory)) {
      mkdirSync(join(root, subdirectory), {mode: 0o755});
      directories.set(subdirectory, lstatSync(join(root, subdirectory)));
    }
    const selected = directories.get(subdirectory), current = lstatSync(join(root, subdirectory));
    if (!current.isDirectory() || current.isSymbolicLink() || !same(selected, current)) {
      fail('ACTQL_E_PROJECT_CHANGED', 'A project subdirectory changed during preparation.');
    }
    const fd = openSync(join(root, name), constants.O_CREAT | constants.O_EXCL |
      constants.O_WRONLY | constants.O_NOFOLLOW, 0o644);
    let failed = false, cause;
    try {
      const opened = fstatSync(fd), bytes = Buffer.from(text);
      if (!opened.isFile() || opened.nlink !== 1) fail('ACTQL_E_PROJECT_CHANGED', 'A project file changed.');
      let offset = 0;
      while (offset < bytes.length) {
        const written = writeSync(fd, bytes, offset, bytes.length - offset);
        if (written === 0) fail('ACTQL_E_PROJECT_WRITE', 'A project write did not complete.');
        offset += written;
      }
      fsyncSync(fd);
    } catch (error) {
      failed = true; cause = error; throw error;
    } finally {
      // Preserve the actual descriptor on an unconfirmed close. No successful
      // preparation receipt can hide an outstanding cleanup responsibility.
      try { closeSync(fd); }
      catch (cleanupCause) { throw Object.assign(new Error('Project file cleanup is unconfirmed.', {
        cause: failed ? cause : cleanupCause,
      }), {
        code: 'ACTQL_E_PROJECT_CLEANUP_PENDING', descriptor: fd, cleanupCause,
      }); }
    }
    created.push(name);
  }
  checkRoot();
  for (const [name, originalDirectory] of directories) {
    const current = lstatSync(join(root, name));
    if (!current.isDirectory() || current.isSymbolicLink() || !same(originalDirectory, current)) {
      fail('ACTQL_E_PROJECT_CHANGED', 'A project subdirectory changed during preparation.');
    }
  }
  return Object.freeze({directory: root, configuration: join(root, 'actql.config.json'),
    stateDirectory: join(root, '.actql'), files: Object.freeze(created)});
}

// This private argv selection requests explicit initial creation; the Native
// session must independently prove exclusive first initialization. It supplies
// no fresh-state witness, default signer, grant or permission itself.
export function projectInitialAdoptionArguments(project, hostConfiguration) {
  const host = hostConfiguration === undefined ? [] : ['--host-config', hostConfiguration];
  return Object.freeze([...host, '--mode', 'local', '--config', project.configuration,
    '--state-dir', project.stateDirectory, 'adopt', '--initialize-signing']);
}

// Parse only the public project-creation spelling. Runtime, approval and Host
// suppliers remain fixed by the installed Native package, never by options.
export function projectInitArguments(args) {
  if (args[0] !== 'init') return undefined;
  if (args.length === 2 && ['--help', '-h'].includes(args[1])) {
    return Object.freeze({help: true});
  }
  let directory, template, hostConfiguration, positional = false;
  for (let index = 1; index < args.length; index++) {
    const value = args[index];
    if (!positional && value === '--') { positional = true; continue; }
    if (!positional && (value === '--template' || value.startsWith('--template='))) {
      if (template !== undefined) fail('ACTQL_E_INIT_ARGUMENTS', 'Select one template.');
      template = value === '--template' ? args[++index] : value.slice('--template='.length);
      if (typeof template !== 'string' || template.length === 0 || template.startsWith('-')) {
        fail('ACTQL_E_INIT_ARGUMENTS', 'The template option needs a name.');
      }
    } else if (!positional && (value === '--host-config' || value.startsWith('--host-config='))) {
      if (hostConfiguration !== undefined) fail('ACTQL_E_INIT_ARGUMENTS', 'Select one Host configuration.');
      hostConfiguration = value === '--host-config' ? args[++index] : value.slice('--host-config='.length);
      if (typeof hostConfiguration !== 'string' || hostConfiguration.length === 0 ||
          hostConfiguration.length > 4096 || hostConfiguration.startsWith('-') || hostConfiguration.includes('\0')) {
        fail('ACTQL_E_INIT_ARGUMENTS', 'The Host configuration option needs a path.');
      }
    } else {
      if (!positional && value.startsWith('-')) {
        fail('ACTQL_E_INIT_ARGUMENTS', 'Unknown init option.');
      }
      if (directory !== undefined) fail('ACTQL_E_INIT_ARGUMENTS', 'Select one project directory.');
      directory = value;
    }
  }
  // Validate before package admission or any filesystem write.
  projectTemplateFiles(template);
  return Object.freeze({directory: directory ?? '.', template,
    ...(hostConfiguration === undefined ? {} : {hostConfiguration})});
}

// Complete original-process diagnostics only. Missing/truncated/foreign rows
// are not zero work. Identities remain opaque original CIDs, never payloads.
export function nativeMockAcceptanceObservations(stderr) {
  sameField(typeof stderr, 'string', 'Native observation stream unavailable');
  assert(stderr.length > 0, 'Missing complete Native observations');
  assert(Buffer.byteLength(stderr) <= 65536, 'Oversized Native diagnostic stream');
  assert(stderr.endsWith('\n'), 'Truncated Native diagnostic row');
  const groups = new Map(), timing = new Map();
  let current;
  const exact = (value, keys) => assert(Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)), 'Invalid Native observation fields');
  function sameField(actual, expected, message = 'Invalid Native diagnostic field') { assert(actual === expected, message); }
  const positive = value => Number.isSafeInteger(value) && value > 0;
  for (const line of stderr.split('\n').slice(0, -1)) {
    assert(/^(ACTQL_NATIVE_TIMINGS|ACTQL_NATIVE_PHASE|ACTQL_NATIVE_COUNTER|ACTQL_NATIVE_ACCEPTANCE_(BEGIN|EVENT|END)) /u.test(line), 'Unknown Native diagnostic row');
    assert(line.length <= 2048, 'Oversized Native observation row');
    const space = line.indexOf(' '), prefix = line.slice(0, space);
    const body = line.slice(space + 1);
    let value;
    try { value = JSON.parse(body); } catch { assert.fail('Malformed Native diagnostic JSON'); }
    assert(value && !Array.isArray(value) && typeof value === 'object', 'Invalid Native diagnostic row');
    sameField(JSON.stringify(value), body, 'Noncanonical or duplicate Native diagnostic fields');
    const amount = value => Number.isSafeInteger(value) && value >= 0;
    if (prefix === 'ACTQL_NATIVE_PHASE' || prefix === 'ACTQL_NATIVE_COUNTER') {
      assert(current && !groups.has(current), 'Out-of-order Native timing row');
      const state = timing.get(current), phase = prefix === 'ACTQL_NATIVE_PHASE';
      const fields = phase ? ['tag','name','begins','ends','inclusive_ns','exclusive_ns','active','overlap','unmatched_end','sql_prepares','current_calls'] : ['tag','name','count'];
      exact(value, fields);
      assert(Number.isInteger(value.tag) && value.tag >= 0 && value.tag < (phase ? 39 : 66), 'Invalid Native timing tag');
      const phaseNames = ['startup','config_auth','preparation','execution','save','close','saved_result','journal'];
      const counterNames = {0:'sqlite_open_calls',1:'sqlite_prepare_calls',2:'sqlite_step_calls',3:'sqlite_exec_calls',16:'member_hash_calls',17:'parse_check_calls',18:'current_calls',19:'account_auth_calls',20:'run_record_save_calls',22:'host_authorize_calls',23:'captured_read_authorize_calls',24:'publisher_authorize_calls',25:'run_record_read_calls',26:'adoption_digest_calls',46:'backing_allocated_bytes',47:'backing_explicit_zeroed_bytes',64:'signing_full_boundary_calls',65:'signing_helper_revalidation_calls'};
      sameField(value.name, phase ? phaseNames[value.tag] ?? {32:'approval_material_complete',33:'approval_reviewer_sign',34:'approval_host_sign',35:'approval_resolution_commit',36:'approval_apply',37:'approval_publish',38:'approval_checkpoint_restore'}[value.tag] ?? 'private_phase' : counterNames[value.tag] ?? 'private_counter', 'Invalid Native timing name');
      assert(fields.filter(key => key !== 'name').every(key => amount(value[key])), 'Invalid Native timing quantity');
      const seen = phase ? state.phases : state.counters;
      assert(!seen.has(value.tag), 'Duplicate Native timing row'); seen.add(value.tag); continue;
    }
    assert(positive(value.pid), 'Invalid Native observation PID');
    if (prefix === 'ACTQL_NATIVE_TIMINGS') {
      exact(value, ['pid','origin','elapsed_ns','clock_current','nested_inclusive','child_process_counters','phase_slots','counter_slots','initializing_drops','invalid_tags','invalid_amounts','clock_failures','overflow','stack_overflows','parallel_observed']);
      assert(timing.size < 2 && !timing.has(value.pid), 'Duplicate or excess Native timing process');
      sameField(value.origin, 'first_hook'); assert(amount(value.elapsed_ns));
      assert(typeof value.clock_current === 'boolean'); sameField(value.nested_inclusive, true);
      sameField(value.phase_slots, 39); sameField(value.counter_slots, 66);
      for (const name of ['invalid_tags','invalid_amounts','clock_failures','stack_overflows']) assert(amount(value[name]), 'Invalid Native recording field');
      assert(typeof value.overflow === 'boolean' && typeof value.parallel_observed === 'boolean');
      // Timing precision/phase diagnostics are not a new acceptance gate.
      // The separate acceptance complete flag owns loss/overflow of events.
      sameField(value.child_process_counters, false, 'Unqualified child counters');
      sameField(value.initializing_drops, 0, 'Incomplete Native observer initialization');
      timing.set(value.pid, {phases: new Set(), counters: new Set()}); current = value.pid; continue;
    }
    if (prefix === 'ACTQL_NATIVE_ACCEPTANCE_BEGIN') {
      exact(value, ['pid', 'count', 'limit', 'complete']);
      assert(current === value.pid && timing.has(value.pid) && !groups.has(value.pid), 'Missing or duplicate Native observation begin');
      sameField(timing.get(value.pid).phases.size, 39, 'Incomplete Native phase rows');
      sameField(timing.get(value.pid).counters.size, 66, 'Incomplete Native counter rows');
      sameField(value.limit, 32); sameField(value.complete, true, 'Incomplete Native observations');
      assert(Number.isSafeInteger(value.count) && value.count >= 0 && value.count <= 32, 'Invalid Native observation count');
      groups.set(value.pid, {pid: value.pid, count: value.count, events: [], ended: false});
    } else if (prefix === 'ACTQL_NATIVE_ACCEPTANCE_EVENT') {
      exact(value, ['pid', 'seq', 'tag', 'ordinal', 'identity']);
      const group = groups.get(value.pid);
      assert(group && !group.ended && group.events.length < group.count, 'Foreign or extra Native event');
      sameField(value.seq, group.events.length, 'Out-of-order Native event');
      assert(Number.isInteger(value.tag) && value.tag >= 0 && value.tag <= 11, 'Invalid Native event kind');
      if (value.tag === 6 || value.tag === 7) {
        sameField(value.ordinal, -1); sameField(value.identity, '');
      } else {
        assert(Number.isSafeInteger(value.ordinal) && value.ordinal >= 0, 'Invalid Native event ordinal');
        assert(typeof value.identity === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value.identity), 'Invalid Native event identity');
      }
      group.events.push(value);
    } else if (prefix === 'ACTQL_NATIVE_ACCEPTANCE_END') {
      exact(value, ['pid', 'count']); const group = groups.get(value.pid);
      assert(group && !group.ended, 'Missing or duplicate Native observation end');
      sameField(value.count, group.count); sameField(group.events.length, group.count, 'Truncated Native observations');
      group.ended = true;
    } else assert.fail('Unknown Native acceptance record');
  }
  assert(groups.size > 0 && timing.size === groups.size && [...groups.values()].every(group => group.ended), 'Missing complete Native observations');
  return [...groups.values()];
}


// Implementation availability only, observed from the same admitted executable.
// A positive answer cannot adopt a Store or supply runtime/Account authority.
export function requireProjectInitSupport(executable, environment, template, query = spawnSync) {
  const observing = environment.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS === '1';
  const child = query(executable, ['project-init-support'], {
    // Default suppression remains; explicit acceptance observes this SAME
    // private query as well as adoption, without changing its support wire.
    env: {...environment, ACTQL_NATIVE_TIMINGS: observing ? '1' : '0'}, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 5000, killSignal: 'SIGKILL', maxBuffer: observing ? 32768 : 4096,
  });
  const unavailable = () => { throw Object.assign(new Error(
    'Native project initialization support is unavailable; no project files were created. Reinstall the fixed package cohort.'), {exitCode: 69}); };
  if (child.error || child.signal || child.status !== 0 || (!observing && child.stderr !== '') ||
      typeof child.stdout !== 'string' || Buffer.byteLength(child.stdout) > 4096) unavailable();
  if (observing) {
    try {
      const observed = nativeMockAcceptanceObservations(child.stderr);
      if (observed.length !== 1 || observed[0].events.length !== 0) unavailable();
    } catch { unavailable(); }
  }
  let support;
  try { support = JSON.parse(child.stdout); } catch { unavailable(); }
  if (!support || Array.isArray(support) || typeof support !== 'object' ||
      Object.keys(support).sort().join(',') !== 'mock,sourceFree,version' ||
      support.version !== 'actql-project-init-support/0.1' ||
      typeof support.sourceFree !== 'boolean' || typeof support.mock !== 'boolean') unavailable();
  // The private Native reply has one fixed spelling and optional final LF.
  // Parsing alone would silently discard duplicate keys or accept other wires.
  const wire = JSON.stringify({version: support.version, sourceFree: support.sourceFree, mock: support.mock});
  if (child.stdout !== wire && child.stdout !== wire + '\n') unavailable();
  // Forward the exact admitted metadata stream in order. Failed diagnostic
  // output remains missing to acceptance; it supplies no successful authority.
  if (observing) { try { writeSync(2, child.stderr); } catch {} }
  // Names and file contents still belong to the existing template preparation.
  // No runtime supplier, grant, signer or fallback is selected by this answer.
  projectTemplateFiles(template);
  if (!(template === undefined ? support.sourceFree : support.mock)) {
    throw Object.assign(new Error(
      'The installed Native runtime does not implement the selected project bindings; no project files were created.'), {exitCode: 69});
  }
}
