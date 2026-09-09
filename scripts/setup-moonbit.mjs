import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyInstallation } from './moonbit-installation.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json'), 'utf8'));
const platform = `${process.platform}-${process.arch}`;
const archive = pin.archives[platform];
if (!archive) throw new Error(`Unsupported development platform: ${platform}`);
const base = join(root, '.toolchains');
const destination = join(base, `moonbit-${pin.version}`);
const marker = JSON.stringify({ pin, platform });
mkdirSync(base, { recursive: true });

function run(command, args, options = {}) {
  execFileSync(command, args, { stdio: 'inherit', ...options });
}

function download(entry, path) {
  run('curl', ['--fail', '--location', '--silent', '--show-error', '--retry', '3', entry.url, '--output', path]);
  const actual = createHash('sha256').update(readFileSync(path)).digest('hex');
  if (actual !== entry.sha256) throw new Error(`SHA-256 mismatch: ${entry.url}`);
}

function verifyTools(install) {
  const env = { ...process.env, MOON_HOME: install, PATH: `${join(install, 'bin')}:${process.env.PATH ?? ''}` };
  const compiler = execFileSync(join(install, 'bin', 'moonc'), ['-v'], { env, encoding: 'utf8' }).trim();
  const buildTool = execFileSync(join(install, 'bin', 'moon'), ['version'], { env, encoding: 'utf8' }).trim().split(/\r?\n/)[0];
  if (compiler !== pin.moonc || buildTool !== `moon ${pin.moon}`) {
    throw new Error(`Toolchain identity mismatch: ${compiler}; ${buildTool}`);
  }
  return env;
}

if (existsSync(destination)) {
  verifyInstallation(destination, marker);
} else {
  // Failed installations remain here for inspection; never replace an existing installation.
  const temporary = mkdtempSync(join(base, 'install-'));
  const install = join(temporary, 'toolchain');
  mkdirSync(install);
  download(archive, join(temporary, 'toolchain.tar.gz'));
  download(pin.core, join(temporary, 'core.tar.gz'));
  run('tar', ['-xzf', join(temporary, 'toolchain.tar.gz'), '-C', install]);
  run('tar', ['-xzf', join(temporary, 'core.tar.gz'), '-C', join(install, 'lib')]);
  for (const entry of readdirSync(join(install, 'bin'), { withFileTypes: true })) {
    if (entry.isFile()) chmodSync(join(install, 'bin', entry.name), 0o755);
  }
  chmodSync(join(install, 'bin', 'internal', 'tcc'), 0o755);
  const env = verifyTools(install);
  const moon = join(install, 'bin', 'moon');
  for (const target of ['js', 'wasm', 'native']) {
    run(moon, ['-C', join(install, 'lib', 'core'), 'bundle', '--target', target, '--warn-list', '-a'], { env });
  }
  writeFileSync(join(install, 'installed.json'), marker);
  verifyInstallation(install, marker);
  renameSync(install, destination);
}
verifyInstallation(destination, marker);
verifyTools(destination);
console.log(`Toolchain ready: ${destination}`);
console.log(`export MOON_HOME="${destination}"`);
console.log('export PATH="$MOON_HOME/bin:$PATH"');
