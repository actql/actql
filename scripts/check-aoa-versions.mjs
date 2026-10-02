import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { machineCid } from './actql-spec-family.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const manifests = [
  ['kernel', 'aoa-kernel-laws', 'kernel_law_manifest_cid', 'aoa-kernel-laws/0.1'],
  ['pipeline', 'aoa-pipeline-laws', 'pipeline_law_manifest_cid', 'aoa-pipeline-laws/0.1'],
  ['scalar', 'aoa-rela-scalar-laws', 'rela_scalar_law_manifest_cid', 'aoa-rela-scalar-laws/0.1'],
  ['primitive', 'aoa-rela-primitive-laws', 'rela_primitive_law_manifest_cid', 'aoa-rela-laws/0.1'],
  ['vector', 'aoa-veca-numeric-laws', 'veca_numeric_law_manifest_cid', 'aoa-veca-numeric-laws/0.1'],
  ['graph', 'aoa-sga-structural-laws', 'sga_structural_law_manifest_cid', 'aoa-sga-structural-laws/0.1'],
  ['graphIdentity', 'aoa-sga-identity-laws', 'sga_identity_law_manifest_cid', 'aoa-sga-identity-laws/0.1'],
  ['propertyGraph', 'aoa-property-graph-laws', 'property_graph_law_manifest_cid', 'aoa-property-graph-laws/0.1'],
];

export function checkVersionTokens(text, context = 'AoA identifier') {
  const pattern = /\baoa-[A-Za-z0-9_-]+\/([0-9]+(?:\.[0-9]+)*)|\baoa\.[A-Za-z0-9_.-]+\.v([0-9]+(?:\.[0-9]+)*)/g;
  for (const match of text.matchAll(pattern)) {
    assert.equal(match[1] ?? match[2], '0.1', `${context}: unexpected version in ${match[0]}`);
  }
}

export function loadDependencies(directory = root) {
  const read = p => JSON.parse(readFileSync(join(directory, p), 'utf8'));
  return {
    contract: read('spec/contracts/actql-aoa.json'),
    bodies: Object.fromEntries(manifests.map(([key, file]) => [key, read(`spec/dependencies/${file}.json`)])),
  };
}

export function checkDependencies({ contract, bodies }) {
  checkVersionTokens(JSON.stringify({ contract, bodies }));
  for (const [key, , pin, version] of manifests) {
    const body = bodies[key];
    assert.ok(body && typeof body === 'object', `Missing ${key} law body`);
    assert.equal(body.manifest_version ?? body.version, version);
    assert.equal(machineCid(body), contract[pin], `${key} law body CID`);
  }
  assert.equal(contract.kernel_law_manifest, bodies.kernel.manifest_version);
  assert.equal(contract.pipeline_law_manifest, bodies.pipeline.manifest_version);
  assert.equal(contract.pipeline_ir_version, 'aoa-pipeline/0.1');
  assert.ok(bodies.pipeline.laws.some(law => law.law_id === contract.effect_plan_law), 'Missing Effect law');
}

export function checkRepository(directory = root) {
  checkDependencies(loadDependencies(directory));
  const scan = path => {
    for (const entry of readdirSync(join(directory, path), { withFileTypes: true })) {
      const file = join(path, entry.name);
      if (entry.isDirectory()) scan(file);
      else if (entry.isFile()) checkVersionTokens(readFileSync(join(directory, file), 'utf8'), file);
    }
  };
  for (const path of ['docs', 'spec', 'src', 'scripts', 'portability']) scan(path);
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.isFile() && /\.(?:md|json)$/.test(entry.name)) {
      checkVersionTokens(readFileSync(join(directory, entry.name), 'utf8'), entry.name);
    }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  checkRepository();
  console.log('AoA 0.1 identifiers and eight exact law-manifest pins verified; not runtime conformance.');
}
