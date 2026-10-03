// Fixed observation driver. Only the recorded input data varies between polls
// of the shrinker; it contains no expected rows or operation-specific branches.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { hash } from './inventory.mjs';
export const fixturePath = 'src/query_integration/relation_pipeline_batch_wbtest.mbt';
export const executionCommand = target => ['moon', 'test', fixturePath, '--target', target, '--deny-warn'];
export const inputVariable = 'ACTQL_RELATION_PIPELINE_CASES';
export const body = `${readFileSync(new URL('./harness.mbt', import.meta.url), 'utf8')}
// Fixed generated observation driver; no expected semantics.
///|
fn relation_pipeline_input_string(value : Json) -> String {
  match value {
    String(s) => s
    _ => abort("pipeline fixture expected string")
  }
}
///|
test "Relation pipeline generated observation batch" {
  let cases = match @json.parse(@env.get_env_var("${inputVariable}").unwrap()) {
    Array(values) => values
    _ => abort("pipeline fixture expected array")
  }
  for item in cases {
    let fields = match item {
      Object(values) => values
      _ => abort("pipeline fixture expected object")
    }
    relation_pipeline_observe(
      relation_pipeline_input_string(fields.get("id").unwrap()),
      relation_pipeline_input_string(fields.get("source").unwrap()),
      relation_pipeline_input_string(fields.get("steps").unwrap()),
      match fields.get("correspondence").unwrap() {
        True => true
        False => false
        _ => abort("pipeline fixture expected boolean")
      },
    )
  }
}
`;
export const payload = (entries, correspondence) => JSON.stringify(entries.map(({ id, program }) => ({
  id, source: program.source, steps: program.steps, correspondence,
})));

// This constant is compiled into the actual test binary, not read from its
// runtime input environment. A stale or other-workspace binary fails closed.
export function boundFixture(boundary) {
  const marker = 'test "Relation pipeline generated observation batch" {\n';
  if (body.split(marker).length !== 2) throw new Error('Ambiguous observation fixture');
  const bindings = ['js', 'wasm', 'native'].map(target => {
    const identity = hash(JSON.stringify({ ...boundary, target, command: executionCommand(target) }));
    return `///|\n#cfg(target="${target}")\nfn relation_pipeline_build_identity() -> String {\n  "ACTQL_PIPELINE_BUILD:${identity}"\n}\n`;
  }).join('\n');
  return bindings + '\n' + body.replace(marker, `${marker}  println(relation_pipeline_build_identity())\n`);
}

// One strict receipt/compiled-fixture contract for both pipeline audits.
// Callers still independently verify source snapshots, inputs, observations,
// semantic/capacity claims and archived artifacts. No legacy-byte fallback.
export function auditFixture(run, fixtureBytes, log, expectedTarget) {
  assert(['js', 'wasm', 'native'].includes(expectedTarget), 'Unknown requested target');
  assert.equal(run.target, expectedTarget, 'Receipt target differs from requested audit target');
  assert.equal(run.exit, 0, 'Failed execution cannot be audited evidence');
  assert.equal(run.boundary.version, 'actql-pipeline-execution-boundary/0.1');
  assert.equal(run.boundary.sourceDigest, run.sourceDigest, 'Compiled source boundary differs');
  assert.equal(run.boundary.target, expectedTarget, 'Compiled target boundary differs');
  assert.deepEqual(run.command, executionCommand(expectedTarget), 'Unreviewed execution command');
  assert.deepEqual(run.boundary.command, run.command, 'Compiled command boundary differs');
  assert.equal(run.boundary.fixtureDigest, hash(body));
  assert(['normal', 'pristine', 'mutable'].includes(run.boundary.role));
  assert.equal(run.buildIdentity, hash(JSON.stringify(run.boundary)), 'Build boundary identity differs');
  const expectedFixture = boundFixture(run.boundary);
  assert.equal(fixtureBytes.toString(), expectedFixture, 'Archived compiled fixture differs');
  assert.equal(run.fixtureDigest, hash(expectedFixture), 'Compiled fixture digest differs');
  assert.deepEqual(log.split('\n').filter(line => line.startsWith('ACTQL_PIPELINE_BUILD:')),
    [`ACTQL_PIPELINE_BUILD:${run.buildIdentity}`], 'Executed binary boundary differs');
  assert.match(log, /Total tests: 1, passed: 1, failed: 0/, 'Observation fixture did not pass exactly once');
}
