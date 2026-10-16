// Private installer preparation. Creating project files does not initialize a
// Host, issue a key, adopt configuration or report a runnable mock installation.
import {constants, closeSync, fstatSync, lstatSync, mkdirSync, openSync,
  opendirSync, realpathSync, writeSync, fsyncSync} from 'node:fs';
import {basename, dirname, join, resolve} from 'node:path';
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
