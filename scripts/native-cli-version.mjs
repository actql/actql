// Explicit immutable compiler DATA for the existing Native artifact owner.
// Nothing here selects a release, invokes a publisher or changes a toolchain.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {access, mkdir, realpath, stat, symlink, writeFile} from 'node:fs/promises';
import {constants} from 'node:fs';
import {dirname, isAbsolute, join, resolve, delimiter} from 'node:path';
import {releaseVersion} from './release-version.mjs';

const macro = '-DACTQL_NATIVE_CLIENT_PACKAGE_VERSION=';
export function nativePackageVersion(value) {
  const selected = releaseVersion(value);
  assert(selected.version.length <= 128, 'Native package version exceeds its finite initial-control bound');
  return selected.version;
}
export function nativeVersionCompilerArguments(args, repository, version) {
  const selected = nativePackageVersion(version);
  assert(isAbsolute(repository)); assert(Array.isArray(args) && args.every(value => typeof value === 'string'));
  assert(!args.some(value => value.startsWith(macro.slice(0, -1))), 'Duplicate Native package version compiler input');
  const sources = args.filter(value => value.endsWith('.c'));
  if (!sources.some(value => resolve(repository, value) === join(repository, 'src/cmd/native_client/version_stub.c')))
    return [...args];
  assert.equal(sources.length, 1); assert(args.includes('-c'), 'Version literal belongs to its original stub compilation');
  return [...args, `${macro}${JSON.stringify(selected)}`];
}

export function executeNativeVersionCompiler(args, {compiler, repository, version}) {
  assert(isAbsolute(compiler));
  const selected = nativeVersionCompilerArguments(args, repository, version);
  const result = spawnSync(compiler, selected, {stdio: 'inherit'});
  if (result.error) throw result.error;
  assert.equal(result.signal, null, 'Original version compiler did not terminate normally');
  return result.status ?? 1;
}

export async function prepareNativeVersionCompiler(directory, repository, version, compiler) {
  const selected = nativePackageVersion(version);
  // Resolve the same ordinary PATH-selected cc before adding the private shim.
  // Never recurse into that shim or silently substitute a different compiler.
  if (compiler === undefined) {
    for (const parent of (process.env.PATH ?? '').split(delimiter)) {
      const path = resolve(parent || '.', 'cc');
      try {
        await access(path, constants.X_OK);
        if ((await stat(path)).isFile()) {compiler = path; break;}
      }
      catch (failure) {if (!['ENOENT', 'EACCES', 'ENOTDIR'].includes(failure.code)) throw failure;}
    }
  }
  assert(compiler && isAbsolute(compiler), 'Select the original normal C compiler');
  await access(compiler, constants.X_OK); assert((await stat(compiler)).isFile(), 'C compiler must be an executable file');
  // Moon selects ar beside the PATH-selected cc, before resolving symlinks.
  // Preserve that companion, rather than selecting an unrelated ar from PATH.
  const companion = join(dirname(compiler), 'ar');
  await access(companion, constants.X_OK); assert((await stat(companion)).isFile(), 'Native archiver must be an executable file');
  const archiver = await realpath(companion); compiler = await realpath(compiler);
  await mkdir(directory, {mode: 0o700});
  await writeFile(join(directory, 'package.json'), '{"private":true,"type":"module"}\n', {flag: 'wx', mode: 0o600});
  const context = {compiler, archiver, repository: resolve(repository), version: selected};
  const bytes = Buffer.from(`#!${process.execPath}\n` +
    `import {executeNativeVersionCompiler} from ${JSON.stringify(import.meta.url)};\n` +
    `process.exitCode=executeNativeVersionCompiler(process.argv.slice(2),${JSON.stringify(context)});\n`);
  const path = join(directory, 'cc'); await writeFile(path, bytes, {flag: 'wx', mode: 0o700});
  await symlink(archiver, join(directory, 'ar'));
  return {path, directory, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), context};
}

// A receipt binds this observation to the actual bytes; it is still build DATA,
// not install/platform/Host acceptance or permission to publish that binary.
export function observeNativePackageVersion(binary, version, execute = spawnSync) {
  const selected = nativePackageVersion(version);
  const result = execute(binary, ['--version'], {encoding: 'utf8', timeout: 10_000, maxBuffer: 65536,
    env: {PATH: '', HOME: '/nonexistent', LANG: 'C'}});
  assert.ifError(result.error); assert.equal(result.signal, null); assert.equal(result.status, 0);
  assert.equal(result.stderr, ''); assert.equal(result.stdout, `${selected}\n`, 'Compiled executable does not display its explicit package version');
  return {argv: ['--version'], stdout: result.stdout, code: result.status, signal: result.signal};
}
