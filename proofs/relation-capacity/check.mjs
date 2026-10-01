import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const cwd = fileURLToPath(new URL('.', import.meta.url));
const model = readFileSync(new URL('Capacity.lean', import.meta.url), 'utf8');
const claims = readFileSync(new URL('Claims.lean', import.meta.url), 'utf8');
const pin = readFileSync(new URL('lean-toolchain', import.meta.url), 'utf8').trim();
const version = spawnSync('lean', ['--short-version'], { cwd, encoding: 'utf8' });
if (version.status !== 0 || version.stdout.trim() !== pin.split(':v')[1]) throw new Error('Wrong Lean pin');
const code = `${model}\n${claims}`.replace(/\/\-[\s\S]*?\-\//g, '').replace(/--[^\n]*/g, '');
if (/\b(sorry|admit|axiom|native_decide|unsafe)\b/.test(code)) throw new Error('Unfinished or unchecked proof');
const names = [...model.matchAll(/^theorem\s+(\w+)/gm)].map(([, name]) => name);
if (names.length !== 14) throw new Error('Review capacity theorem inventory');
const audit = names.map(name => `#print axioms RelationCapacity.${name}`).join('\n');
const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], {
  cwd, encoding: 'utf8', input: `${model}\n${claims}\n${audit}\n`, maxBuffer: 4 * 1024 * 1024,
});
process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || '');
if (result.error) throw result.error;
if (result.status !== 0 || /sorryAx/.test(result.stdout)) process.exit(1);
for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/g)) {
  if (axioms.split(',').some(name => !['propext', 'Quot.sound'].includes(name.trim()))) throw new Error(`Unexpected axioms: ${axioms}`);
}
console.log(`Checked ${names.length} capacity theorems, expected types and axiom dependencies; child/parent bounds are premises`);
