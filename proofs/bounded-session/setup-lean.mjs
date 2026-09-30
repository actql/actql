// CI-only installation of the same Lean pin as managed-retained. The archive
// digest is the release asset's SHA-256, not a mutable installer script.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

if (process.platform !== 'linux' || process.arch !== 'x64') throw new Error('CI installer supports Linux x64 only');
const root = fileURLToPath(new URL('../../', import.meta.url));
const pin = readFileSync(new URL('lean-toolchain', import.meta.url), 'utf8').trim();
if (pin !== 'leanprover/lean4:v4.30.0-rc1') throw new Error('Update and audit the archive pin together');
const version = pin.split(':v')[1];
const directory = join(root, '.toolchains');
const destination = join(directory, `lean-${version}-linux`);
mkdirSync(directory, { recursive: true });
if (!existsSync(destination)) {
  const archive = join(directory, `lean-${version}-linux.tar.zst`);
  execFileSync('curl', ['--fail', '--location', '--silent', '--show-error', '--retry', '3',
    `https://github.com/leanprover/lean4/releases/download/v${version}/lean-${version}-linux.tar.zst`, '--output', archive], { stdio: 'inherit' });
  const digest = createHash('sha256').update(readFileSync(archive)).digest('hex');
  if (digest !== '37c2913cf41b49f33ab2eebc449d12394081817315c9f915af1ff43f1642de42') throw new Error('Lean archive digest mismatch');
  execFileSync('tar', ['--zstd', '-xf', archive, '-C', directory], { stdio: 'inherit' });
}
const actual = execFileSync(join(destination, 'bin/lean'), ['--short-version'], { encoding: 'utf8' }).trim();
if (actual !== version) throw new Error('Lean executable pin mismatch');
console.log(destination);
