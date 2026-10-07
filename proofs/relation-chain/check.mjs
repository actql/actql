import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const cwd = fileURLToPath(new URL('.', import.meta.url));
const modules = [
  ['BoundedSession', '../bounded-session/Session.lean', 14],
  ['RelationChain', 'Chain.lean', 22],
  ['RelationChainStop', 'StopAccounting.lean', 14],
].map(([namespace, path, count]) => ({namespace, count,
  source: readFileSync(new URL(path, import.meta.url), 'utf8')}));
const model = modules.map(m => m.source).join('\n');
const claims = ['Claims.lean', 'StopClaims.lean']
  .map(path => readFileSync(new URL(path, import.meta.url), 'utf8')).join('\n');
const pin = readFileSync(new URL('lean-toolchain', import.meta.url), 'utf8').trim();
const version = spawnSync('lean', ['--short-version'], { cwd, encoding: 'utf8' });
if (version.status !== 0 || version.stdout.trim() !== pin.split(':v')[1]) {
  throw new Error(`Expected ${pin}; got ${version.stdout || version.stderr}`);
}
// Strip comments before checking tokens; the full source still goes to Lean.
const code = `${model}\n${claims}`.replace(/\/\-[\s\S]*?\-\//g, '').replace(/--[^\n]*/g, '');
if (/\b(sorry|admit|axiom|native_decide|unsafe)\b/.test(code)) {
  throw new Error('Unfinished proofs, custom axioms and unchecked decisions are forbidden');
}
const names = modules.flatMap(m => {
  const names = [...m.source.matchAll(/^theorem\s+(\w+)/gm)].map(([, name]) => `${m.namespace}.${name}`);
  if (names.length !== m.count || new Set(names).size !== names.length)
    throw new Error(`Review the expected ${m.namespace} theorem inventory`);
  return names;
});
const audit = names.map(name => `#print axioms ${name}`).join('\n');
const result = spawnSync('lean', ['-DwarningAsError=true', '--stdin'], {
  cwd, encoding: 'utf8', input: `${model}\n${claims}\n${audit}\n`, maxBuffer: 4 * 1024 * 1024,
});
process.stdout.write(result.stdout || '');
process.stderr.write(result.stderr || '');
if (result.error) throw result.error;
if (result.status !== 0 || /sorryAx/.test(result.stdout)) process.exit(1);
for (const [, axioms] of result.stdout.matchAll(/depends on axioms: \[([^\]]*)\]/g)) {
  if (axioms.split(',').some(name => !['propext', 'Quot.sound'].includes(name.trim()))) {
    throw new Error(`Unexpected proof axiom: ${axioms}`);
  }
}
console.log(`Checked ${names.length} theorems, expected claim types and axiom dependencies`);
