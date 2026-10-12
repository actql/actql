import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';

const corpus = 'portability/corpus/model-raw-capture.json';
const output = 'src/run_publication/model_raw_capture.generated_test.mbt';
// Independent flat fixtures contain only scalars. Do not import the product
// canonicalizer or fill expected identities from the product generator.
const canonical = body => JSON.stringify(body, Object.keys(body).sort());
export function rawCaptureVectors() {
  const fixtures = JSON.parse(readFileSync(corpus, 'utf8'));
  let source = '// Generated from independent model-raw-capture corpus.\n';
  for (const c of fixtures.cases) {
    const body = canonical(c.body);
    assert.equal(`sha256:${createHash('sha256').update(body).digest('hex')}`,
      c.expected_cid, c.name);
    const complete = canonical({...c.body, self_cid: c.expected_cid});
    const foreign = canonical({...c.body, self_cid: `sha256:${'0'.repeat(64)}`});
    const extra = canonical({...c.body, complete: true});
    const missing = {...c.body};
    delete missing.version;
    const invalidBodies = [extra, canonical(missing)];
    if (c.kind === 'model_raw_response') {
      for (const [field, value] of [['attempt', 2], ['phase', 'settled'],
        ['http_status', 99], ['http_status', 600], ['byte_count', -1],
        ['byte_count', 2147483648], ['transport_eof', null]]) {
        invalidBodies.push(canonical({...c.body, [field]: value}));
      }
    }
    source += `\n///|\ntest ${JSON.stringify(c.name)} {\n` +
      `  let body = ${JSON.stringify(body)}\n` +
      `  let wire = ${JSON.stringify(complete)}\n` +
      `  let issued = seal_run_evidence_value(${JSON.stringify(c.kind)}, body, 8192, 128, 8).unwrap()\n` +
      `  assert_eq(run_evidence_value_identity(issued), ${JSON.stringify(c.expected_cid)})\n` +
      `  assert_eq(run_evidence_value_json(issued), wire)\n` +
      `  let restored = admit_run_evidence_value(${JSON.stringify(c.kind)}, wire, 8192, 128, 8).unwrap()\n` +
      `  assert_eq(run_evidence_value_json(restored), wire)\n` +
      `  assert_true(admit_run_evidence_value(${JSON.stringify(c.kind)}, ${JSON.stringify(foreign)}, 8192, 128, 8) is Err(RunEvidenceIdentityMismatch))\n` +
      `  assert_true(admit_run_evidence_value(${JSON.stringify(c.kind)}, " " + wire, 8192, 128, 8) is Err(RunEvidenceInvalidWire))\n` +
      `  for invalid in [${invalidBodies.map(JSON.stringify).join(',')}, body.replace(old="/0.1", new="/9.9")] {\n` +
      `    assert_true(seal_run_evidence_value(${JSON.stringify(c.kind)}, invalid, 8192, 128, 8) is Err(RunEvidenceInvalidShape))\n` +
      `  }\n` +
      `  assert_true(admit_run_evidence_value(${JSON.stringify(c.kind)}, wire, 32, 128, 8) is Err(_))\n` +
      `}\n`;
  }
  source = execFileSync(process.env.MOON_HOME
    ? join(process.env.MOON_HOME, 'bin/moonfmt') : 'moonfmt', ['-'],
  {input: source, encoding: 'utf8'});
  return {fixtures, source};
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const {source} = rawCaptureVectors();
  if (process.argv.includes('--write')) writeFileSync(output, source);
  else assert.equal(readFileSync(output, 'utf8'), source);
  console.log('2 independent raw capture vectors verified.');
}
