import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid, documentCid, fingerprint} from './actql-spec-family.mjs';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';

const profilesPath = 'spec/contracts/actql-production-profile-schemas.json';
const protocolPath = 'spec/contracts/actql-protocol-schemas.json';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const cid = {type: 'string', pattern: '^sha256:[a-f0-9]{64}$'};
const originalStaticPin = 'sha256:587bfea69fbab0d23d200ac65ffc20c373142c4843820d37db6e0c617f10206a';

// The old static body stays a closed branch with its original preimages.
// The runtime branch identifies the SAME finite checked policy obligation;
// neither its CID nor complete-per-key semantics attests to resource admission.
export function lookupBarrierSchema(original) {
  const {$schema, $id} = original;
  const staticBody = structuredClone(original.oneOf?.[0] ?? original);
  delete staticBody.$schema;
  delete staticBody.$id;
  assert.equal(machineCid({$schema, $id, ...staticBody}), originalStaticPin,
    'Changed original static lookup barrier contract');
  const runtime = structuredClone(staticBody);
  const removed = new Set(['bounds', 'capacity_proof_cid']);
  runtime.required = runtime.required.filter(name => !removed.has(name));
  for (const name of removed) delete runtime.properties[name];
  runtime.required.push('lookup_execution_cid');
  runtime.properties.lookup_execution_cid = cid;
  // Completeness and admission are different axes. No hard-limit-only result
  // is substituted for the checked complete-per-requested-key acquisition.
  runtime.properties.capacity_guarantee = {const: 'complete'};
  for (const field of ['effective_request_classification',
    'effective_response_classification', 'effective_output_classification']) {
    runtime.properties[field].enum.push('unknown');
  }
  return {$schema, $id, oneOf: [staticBody, runtime]};
}

export function runtimeLookupSummary(original) {
  const staticBody = structuredClone(original.oneOf?.[0] ?? original);
  assert.equal(staticBody.additionalProperties, false);
  assert.ok(staticBody.required.includes('capacity_proof_cid'));
  assert.ok(staticBody.required.includes('max_distinct_keys'));
  const runtime = structuredClone(staticBody);
  for (const name of ['capacity_proof_cid', 'max_distinct_keys']) {
    runtime.required = runtime.required.filter(key => key !== name);
    delete runtime.properties[name];
  }
  runtime.required = runtime.required.filter(name => name !== 'max_output_rows');
  runtime.required.push('lookup_execution_cid');
  runtime.properties.lookup_execution_cid = cid;
  return {oneOf: [staticBody, runtime]};
}

export function lookupSummarySlots(planResult) {
  const slots = [];
  for (const branch of planResult.oneOf) {
    const joins = branch.properties?.summary?.properties?.external_joins;
    if (joins) slots.push(joins);
  }
  assert.equal(slots.length, 2, 'Both existing plan_result summaries');
  return slots;
}

function refreshFamilyPins() {
  const path = 'spec/spec-family.json', family = read(path);
  for (const owner of family.documents) {
    let document = readFileSync(owner.path, 'utf8');
    for (const imported of owner.machine_contracts ?? []) {
      if (![profilesPath, protocolPath, 'spec/manifests/actql-barrier-contracts-0.1.json'].includes(imported.path)) continue;
      let body = read(imported.path);
      for (const key of imported.pointer.split('/').slice(1)) {
        body = body[key.replaceAll('~1', '/').replaceAll('~0', '~')];
      }
      const pin = machineCid(body);
      document = document.replaceAll(
        `../../../${imported.path}#${imported.pointer} ${imported.cid}`,
        `../../../${imported.path}#${imported.pointer} ${pin}`);
      imported.cid = pin;
    }
    writeFileSync(owner.path, document);
  }
  // Exact-artifact law blocks include their machine pins. Refresh only the
  // derived statement fingerprint under the SAME existing requirement ID and
  // status; no old implementation or runtime evidence is promoted.
  for (const owner of family.documents) {
    const document = readFileSync(owner.path, 'utf8');
    const marker = '<!-- requirement-block: machine-contracts.exact-artifacts -->';
    const start = document.indexOf(marker);
    if (start < 0) continue;
    const end = document.indexOf('<!-- requirement-block:', start + marker.length);
    const clauses = normalizedParagraphs(document.slice(start + marker.length,
      end < 0 ? document.length : end));
    assert.equal(clauses.length, 1);
    const evidence = read(owner.evidence);
    const entry = evidence.requirements.find(entry =>
      entry.requirement_id === owner.spec_id + '/machine-contracts.exact-artifacts');
    assert.ok(entry);
    entry.statement_sha256 = fingerprint(clauses[0]);
    writeFileSync(owner.evidence, JSON.stringify(evidence, null, 2) + '\n');
  }
  const documents = new Map(family.documents.map(owner =>
    [owner.spec_id, documentCid(readFileSync(owner.path, 'utf8'))]));
  for (const owner of family.documents) for (const imported of owner.normative_imports ?? []) {
    imported.document_cid = documents.get(imported.owner);
  }
  writeFileSync(path, JSON.stringify(family, null, 2) + '\n');
}

export function verifyLookupBarrierSchemas(write = false) {
  const profiles = read(profilesPath), protocol = read(protocolPath);
  const schema = lookupBarrierSchema(profiles.schemas.lookup_barrier);
  const slots = lookupSummarySlots(protocol.artifact_schemas.plan_result);
  const summaries = slots.map(slot => runtimeLookupSummary(slot.items));
  assert.deepEqual(summaries[0], summaries[1]);
  if (write) {
    profiles.schemas.lookup_barrier = schema;
    profiles.schema_cids.lookup_barrier = machineCid(schema);
    const {registry_cid: _previous, ...body} = profiles;
    profiles.registry_cid = machineCid(body);
    for (let i = 0; i < slots.length; i++) slots[i].items = summaries[i];
    protocol.artifact_schema_cids.plan_result = machineCid(protocol.artifact_schemas.plan_result);
    protocol.artifact_registry_cid = machineCid(protocol.artifact_schemas);
    writeFileSync(profilesPath, JSON.stringify(profiles, null, 2) + '\n');
    writeFileSync(protocolPath, JSON.stringify(protocol, null, 2) + '\n');
    refreshFamilyPins();
  }
  assert.deepEqual(profiles.schemas.lookup_barrier, schema);
  assert.equal(profiles.schema_cids.lookup_barrier, machineCid(schema));
  const {registry_cid: registryCid, ...body} = profiles;
  assert.equal(registryCid, machineCid(body));
  for (let i = 0; i < slots.length; i++) assert.deepEqual(slots[i].items, summaries[i]);
  assert.equal(protocol.artifact_schema_cids.plan_result, machineCid(protocol.artifact_schemas.plan_result));
  assert.equal(protocol.artifact_registry_cid, machineCid(protocol.artifact_schemas));
  return {schema, summaries, staticPin: originalStaticPin};
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const {schema, staticPin} = verifyLookupBarrierSchemas(process.argv.includes('--write'));
  console.log(JSON.stringify({lookup_barrier: machineCid(schema), retained_static_schema: staticPin,
    qualification: 'Contract DATA only; no runtime capacity or completed acquisition'}));
}
