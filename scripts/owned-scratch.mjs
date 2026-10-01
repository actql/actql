// A scratch directory owned by one test process: created here with
// mkdtemp, removed only by this handle, and only after the test said it
// passed. The decision is taken when the process exits:
//
// - a failing exit keeps the directory for diagnosis and prints how to
//   remove it, without adding to or replacing the original failure;
// - a zero exit without `passed()` keeps it and exits 1: the test did not
//   confirm that everything it started in the directory has ended;
// - ACTQL_TEST_PRESERVE_SCRATCH=1 keeps it and prints how to remove it;
// - otherwise the named artifacts' digests and the directory's file volume
//   are printed, the directory is removed, and its absence is checked. A
//   removal that fails or leaves the directory keeps it and exits 2, so a
//   passed test with a failed cleanup is never reported as success.
//
// Nothing outside the created directory is touched. Symbolic links inside
// it are removed as links; their targets are neither measured nor removed.
import {createHash} from 'node:crypto';
import {existsSync, lstatSync, readdirSync, readFileSync, rmSync} from
  'node:fs';
import {mkdir, mkdtemp} from 'node:fs/promises';
import {join} from 'node:path';

export const CLEANUP_FAILED_EXIT = 2;
export const UNCONFIRMED_EXIT = 1;

const quote = path => `'${path.replaceAll("'", "'\\''")}'`;

// Regular files below `path`, without following symbolic links.
function volume(path) {
  let bytes = 0;
  let files = 0;
  const visit = current => {
    for (const entry of readdirSync(current, {withFileTypes: true})) {
      const child = join(current, entry.name);
      if (entry.isDirectory()) visit(child);
      else if (entry.isFile()) {
        bytes += lstatSync(child).size;
        files += 1;
      }
    }
  };
  visit(path);
  return {bytes, files};
}

const megabytes = bytes => `${(bytes / 1024 / 1024).toFixed(1)} MiB`;

// Create the directory `<parent>/<prefix>XXXXXX`. `label` names the test in
// the messages; `digests` lists file names at the top of the directory whose
// sha256 is printed before removal (for example the installed tarballs).
export async function createOwnedScratch({parent, prefix, label,
  digests = () => []}) {
  await mkdir(parent, {recursive: true});
  const path = await mkdtemp(join(parent, prefix));
  let passed = false;
  const keep = reason => {
    console.error(`${label}: ${reason}; scratch kept: ${path}`);
    console.error(`${label}: remove it after inspection with: rm -rf -- ${
      quote(path)}`);
  };
  process.once('exit', code => {
    if (code !== 0) {
      keep('test failed');
      return;
    }
    if (!passed) {
      keep('the test did not confirm that its processes ended');
      process.exitCode = UNCONFIRMED_EXIT;
      return;
    }
    if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
      keep('test passed, preservation requested');
      return;
    }
    let measured;
    try {
      for (const name of digests()) {
        const digest = createHash('sha256').update(readFileSync(join(path,
          name))).digest('hex');
        console.log(`${label}: ${name} sha256:${digest}`);
      }
      measured = volume(path);
      rmSync(path, {recursive: true});
      if (existsSync(path)) throw new Error('directory still present');
    } catch (error) {
      console.error(`${label}: test passed; cleanup failed: ${error.message}`);
      keep('cleanup failed');
      process.exitCode = CLEANUP_FAILED_EXIT;
      return;
    }
    console.log(`${label}: removed ${path} (${measured.files} files, ${
      megabytes(measured.bytes)} before removal)`);
  });
  return Object.freeze({
    path,
    // Call when the test passed and every process, Host and Store it
    // started in the directory has ended.
    passed() { passed = true; },
  });
}
