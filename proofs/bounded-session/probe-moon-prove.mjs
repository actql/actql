// Capability probe on the exact production function. This is deliberately
// separate from accepted evidence: success would still require proof contracts,
// call-site range premises and a solver/trust audit before claiming refinement.
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const pin = JSON.parse(readFileSync(join(root, 'toolchain.json'), 'utf8'));
const home = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
const source = readFileSync(join(root, 'src/bounded_execution/session.mbt'), 'utf8');
const start = source.indexOf('fn add_counter(');
if (start < 0) throw new Error('Production counter function missing');
const end = source.indexOf('\n///|', start);
const body = source.slice(start, end);
const directory = mkdtempSync(join(tmpdir(), 'actql-moon-prove-'));
writeFileSync(join(directory, 'moon.mod'), 'name = "actql/counter-probe"\n');
mkdirSync(join(directory, 'counter'));
writeFileSync(join(directory, 'counter/moon.pkg'), 'options("proof-enabled": true)\n');
const annotated = body.replace('fn add_counter', 'pub fn add_counter').replace('-> Int64? {', `-> Int64? where {
  proof_require: current >= 0L,
  proof_ensure: result => match result {
    None => delta < 0 || delta.to_int64() > 9223372036854775807L - current
    Some(total) => total >= current && total <= 9223372036854775807L &&
      total - current == delta.to_int64()
  },
} {`);
writeFileSync(join(directory, 'counter/counter.mbt'), annotated);
const result = spawnSync(join(home, 'bin/moon'), ['prove', 'counter', '--deny-warn'], {
  cwd: directory, env: { ...process.env, MOON_HOME: home, PATH: `${home}/bin:${process.env.PATH}` },
  encoding: 'utf8', timeout: 60000,
});
console.log(JSON.stringify({
  kind: 'capability-probe', source: 'src/bounded_execution/session.mbt:add_counter',
  directory, exit: result.status, error: result.error?.message ?? null,
  stdout: result.stdout, stderr: result.stderr,
}, null, 2));
if (result.error) process.exitCode = 1;
