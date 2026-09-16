import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const cwd = fileURLToPath(new URL('.', import.meta.url));
const source = readFileSync(new URL('ManagedBoundary.lean', import.meta.url), 'utf8');
const pin = readFileSync(new URL('lean-toolchain', import.meta.url), 'utf8').trim();
const version = spawnSync('lean', ['--short-version'], { cwd, encoding: 'utf8' });
if (version.status !== 0 || version.stdout.trim() !== pin.split(':v')[1]) {
  throw new Error(`Expected installed Lean ${pin}; got ${version.stdout || version.stderr}`);
}
if (/\b(sorry|admit|axiom|native_decide)\b/.test(source)) {
  throw new Error('Unfinished proofs, custom axioms and unchecked native decisions are forbidden');
}
const audit = [...source.matchAll(/^theorem\s+(\w+)/gm)]
  .map(([, name]) => `#print axioms ManagedBoundary.${name}`).join('\n');
const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], {
  cwd, encoding: 'utf8', input: `${source}\n${audit}\n`, maxBuffer: 4 * 1024 * 1024,
});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if (result.error) throw result.error;
if (result.status !== 0 || /sorryAx/.test(result.stdout)) process.exit(1);
for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/g)) {
  if (axioms.split(',').some((name) => !['propext', 'Quot.sound'].includes(name.trim()))) {
    throw new Error(`Unexpected proof axiom: ${axioms}`);
  }
}
