import assert from 'node:assert/strict';

// Real Local files acquisition, serialization, checked Result imports and an
// ordinary approved STORE row for every group Result.
// Each group's declared ports remain independently observed imports of the same
// completed producer; none is replaced by a fabricated dependency DATA body.
export function projectFileDependencyBoundary({ports = 2050, groups = 8} = {}) {
  assert(Number.isSafeInteger(ports) && ports > 0);
  assert(Number.isSafeInteger(groups) && groups > 0 && groups <= ports && groups <= 30);
  const path = 'original.jsonl';
  const body = '{"actual":"source"}\n';
  const inputBytes = Buffer.byteLength(body);
  const contentFields = ['name', 'content', 'media_type', 'size_bytes', 'row_count'];
  const acquisition = {id: 'acquire', inputs: {files: {connector: 'source',
    resource: 'files', request: {paths: null, glob: null}}}, from: 'files',
  steps: [{select: ['path', 'size_bytes'], as: 'captured'}],
  results: {rows: {from: 'captured', fields: ['path', 'size_bytes']}}};
  const producer = {id: 'content', inputs: {rows: {result: {stage: acquisition.id, result: 'rows'}}},
  from: 'rows', steps: [{assert_rows: {unique_by: ['path']}, as: 'keyed'},
    {from: 'keyed', sort: [{field: 'path', dir: 'asc', nulls: 'last'}], as: 'ordered'},
    {from: 'ordered', serialize: {format: 'jsonl', fields: ['path', 'size_bytes'], name: 'boundary.jsonl',
    preserve_order: true, bounds: {max_rows: 1, max_bytes: 256}}, as: 'attachment'}],
  results: {rows: {from: 'attachment', fields: contentFields}}};
  const stages = [acquisition, producer];
  const groupSizes = Array.from({length: groups}, (_, index) =>
    Math.floor(ports / groups) + (index < ports % groups ? 1 : 0));
  const finalInputs = {};
  const results = {producer: {from: {stage: acquisition.id, result: 'rows'}},
    serialized: {from: {stage: producer.id, result: 'rows'}}};
  for (let group = 0; group < groups; group++) {
    const id = `group${group}`;
    // The interface preimage names the input and producer, not the consumer
    // Unit. Distinct real input names keep all checked interfaces distinct.
    const inputs = Object.fromEntries(Array.from({length: groupSizes[group]}, (_, index) =>
      [`g${group}_i${index}`, {result: {stage: producer.id, result: 'rows'}}]));
    stages.push({id, inputs, from: `g${group}_i0`, steps: [
      {select: contentFields, as: 'imported'},
      {from: 'imported', derive: {path: {literal: `dependency-${String(group).padStart(2, '0')}.jsonl`}}, as: 'marked'},
    ], results: {rows: {from: 'marked', fields: [...contentFields, 'path']}}});
    finalInputs[`g${group}`] = {result: {stage: id, result: 'rows'}};
    results[id] = {from: {stage: id, result: 'rows'}};
  }
  const steps = [];
  let current = 'g0';
  for (let group = 1; group < groups; group++) {
    const next = `combined${group}`;
    steps.push({from: current, append: {with: `g${group}`}, as: next});
    current = next;
  }
  steps.push({from: current,
    sort: [{field: 'path', dir: 'asc', nulls: 'last'}], as: 'ordered'});
  stages.push({id: 'apply', inputs: finalInputs, steps,
    results: {content: {from: 'ordered', fields: [...contentFields, 'path']}},
    effects: {save: {command: {from: {result: 'content'},
      target: {published_store: {target_ref: 'connector://destination/files',
        mapping_ref: 'mapping:destination.local.files.store.v1'}},
      contract: 'command:destination.local.files.store.v1',
      input: {path: {field: 'path'}, content: {field: 'content'}}}}}});
  results.answer = {from: {stage: 'apply', result: 'content'}};
  const program = {version: 'actql/0.1', id: 'ordinary-complete-dependency-groups',
    stages, results};
  const expectedBody = JSON.stringify({path, size_bytes: inputBytes}) + '\n';
  const expectedSerialized = {name: 'boundary.jsonl', media_type: 'application/x-ndjson',
    size_bytes: Buffer.byteLength(expectedBody), row_count: 1};
  const expectedRows = Array.from({length: groups}, (_, index) =>
    ({...expectedSerialized, path: `dependency-${String(index).padStart(2, '0')}.jsonl`}));
  return Object.freeze({name: 'project-file-complete-dependency', format: 'json',
    source: JSON.stringify(program), program, groupSizes: Object.freeze(groupSizes),
    imports: 1 + ports + groups, expectedDefinitions: 1, expectedWrites: groups,
    inputs: Object.freeze([Object.freeze({path, body})]),
    expectedRows: Object.freeze(expectedRows.map(Object.freeze)),
    expectedProducer: Object.freeze([Object.freeze({path, size_bytes: inputBytes})]),
    expectedSerialized: Object.freeze([Object.freeze(expectedSerialized)]),
    resultName: 'answer', expectedFiles: Object.freeze(expectedRows.map(row =>
      Object.freeze({path: row.path, body: expectedBody}))),
    expectedProjection: Object.freeze(expectedRows.map(Object.freeze))});
}
