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
export function projectInitialAdoptionArguments(project) {
  return Object.freeze(['--mode', 'local', '--config', project.configuration,
    '--state-dir', project.stateDirectory, 'adopt', '--initialize-signing']);
}

// Parse only the public project-creation spelling. Runtime, approval and Host
// suppliers remain fixed by the installed Native package, never by options.
export function projectInitArguments(args) {
  if (args[0] !== 'init') return undefined;
  if (args.length === 2 && ['--help', '-h'].includes(args[1])) {
    return Object.freeze({help: true});
  }
  let directory, template, positional = false;
  for (let index = 1; index < args.length; index++) {
    const value = args[index];
    if (!positional && value === '--') { positional = true; continue; }
    if (!positional && (value === '--template' || value.startsWith('--template='))) {
      if (template !== undefined) fail('ACTQL_E_INIT_ARGUMENTS', 'Select one template.');
      template = value === '--template' ? args[++index] : value.slice('--template='.length);
      if (typeof template !== 'string' || template.length === 0 || template.startsWith('-')) {
        fail('ACTQL_E_INIT_ARGUMENTS', 'The template option needs a name.');
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
  return Object.freeze({directory: directory ?? '.', template});
}

// Implementation availability only, observed from the same admitted executable.
// A positive answer cannot adopt a Store or supply runtime/Account authority.
export function requireProjectInitSupport(executable, environment, template, query = spawnSync) {
  const child = query(executable, ['project-init-support'], {
    env: environment, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 5000, killSignal: 'SIGKILL', maxBuffer: 4096,
  });
  const unavailable = () => { throw Object.assign(new Error(
    'Native project initialization support is unavailable; no project files were created. Reinstall the fixed package cohort.'), {exitCode: 69}); };
  if (child.error || child.signal || child.status !== 0 || child.stderr !== '' ||
      typeof child.stdout !== 'string' || Buffer.byteLength(child.stdout) > 4096) unavailable();
  let support;
  try { support = JSON.parse(child.stdout); } catch { unavailable(); }
  if (!support || Array.isArray(support) || typeof support !== 'object' ||
      Object.keys(support).sort().join(',') !== 'mock,sourceFree,version' ||
      support.version !== 'actql-project-init-support/0.1' ||
      typeof support.sourceFree !== 'boolean' || typeof support.mock !== 'boolean') unavailable();
  // Names and file contents still belong to the existing template preparation.
  // No runtime supplier, grant, signer or fallback is selected by this answer.
  projectTemplateFiles(template);
  if (!(template === undefined ? support.sourceFree : support.mock)) {
    throw Object.assign(new Error(
      'The installed Native runtime does not implement the selected project bindings; no project files were created.'), {exitCode: 69});
  }
}
