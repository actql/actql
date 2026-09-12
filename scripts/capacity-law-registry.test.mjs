import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { machineCid } from './actql-spec-family.mjs';
import { validateRegistry, loadRegistry, renderRegistry, renderGuardLaws } from './capacity-law-registry.mjs';

test('Graph count body fixes quantity transfers and independent selector arithmetic', () => {
  const path = 'spec/contracts/actql-bound-graph-laws.json';
  const body = JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
  const cid = 'sha256:5e9a00ff401f42059f037c52babb40f8440201b3dccaffa90da297058d6adc89';
  assert.equal(machineCid(body), cid);
  for (const law of body.law_ids) assert.ok(loadRegistry().body.law_ids.includes(law));
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  assert.ok(family.documents.flatMap(d => d.machine_contracts ?? []).some(r => r.path === path && r.pointer === '' && r.cid === cid && r.version === body.version));
  const implementation = readFileSync(new URL('../src/pipeline_check_context/core_contracts.mbt', import.meta.url), 'utf8');
  assert.ok(implementation.replace(/\s+/g, ' ').includes(`GraphCountRules => "${cid}"`));
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/bound-graph.json', import.meta.url), 'utf8'));
  assert.equal(corpus.version, 'actql-bound-graph-vectors/0.1');
  for (const v of corpus.cases) {
    const [a,b] = v.inputs.map(BigInt);
    let n;
    switch (v.rule) {
      case 'endpoints': n = 2n*a; break;
      case 'preserve': case 'nearest_per_source': n = a; break;
      case 'sum': n = v.inputs.reduce((n,x) => n+BigInt(x),0n); break;
      case 'traverse': n = (a < b ? a : b)*b; break;
      case 'each_pair': n = a*b; break;
      case 'nearest_pair': n = 1n; break;
      default: assert.fail(v.rule);
    }
    if (n > 9007199254740991n) assert.equal(v.error,'Overflow');
    else { assert.equal(v.error,undefined); assert.equal(n,BigInt(v.expected)); }
  }
});

test('window count semantics and independent membership bounds are pinned', () => {
  const path = 'spec/contracts/actql-bound-window-laws.json';
  const body = JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
  const cid = 'sha256:a5045688150b6b5aaf0c992b2e528ba3b5f1dd49e0db14e5673c9515af82ac3a';
  assert.equal(machineCid(body), cid);
  for (const law of body.law_ids) assert.ok(loadRegistry().body.law_ids.includes(law));
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  assert.ok(family.documents.flatMap(d => d.machine_contracts ?? []).some(r => r.path === path && r.pointer === '' && r.cid === cid && r.version === body.version));
  const implementation = readFileSync(new URL('../src/pipeline_check_context/core_contracts.mbt', import.meta.url), 'utf8');
  assert.ok(implementation.replace(/\s+/g, ' ').includes(`WindowCountRules => "${cid}"`));
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/bound-window.json', import.meta.url), 'utf8'));
  assert.equal(corpus.version, 'actql-bound-window-vectors/0.1');
  for (const v of corpus.cases) {
    const valid = Number.isSafeInteger(v.size) && v.size > 0 && Number.isSafeInteger(v.offset)
      && (v.step === null ? v.kind === 'fixed' : Number.isSafeInteger(v.step) && v.step > 0);
    if (!valid) { assert.equal(v.error, 'InvalidOption'); continue; }
    const size = BigInt(v.size), step = BigInt(v.step ?? v.size);
    const factor = v.kind === 'fixed' ? 1n : (size + step - 1n) / step;
    const n = BigInt(v.input) * factor;
    if (n > 9007199254740991n) assert.equal(v.error, 'Overflow');
    else { assert.equal(v.error, undefined); assert.equal(n, BigInt(v.expected)); }
  }
  // Independently enumerate closed-open memberships across negative and positive
  // grids; the maximum must attain, and never exceed, the proposed multiplier.
  for (let size = 1; size <= 12; size++) for (let step = 1; step <= 12; step++) {
    for (let offset = -3; offset <= 3; offset++) {
      let peak = 0;
      for (let t = -24; t <= 24; t++) {
        let count = 0;
        for (let n = -50; n <= 50; n++) {
          const start = offset + n * step;
          if (start <= t && t < start + size) count++;
        }
        peak = Math.max(peak, count);
      }
      assert.equal(peak, Math.ceil(size / step));
    }
  }
});

test('join count body is pinned and selected by the compiler', () => {
  const path = 'spec/contracts/actql-bound-join-laws.json';
  const body = JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
  const cid = 'sha256:75f9c5ce5188d28a2e3b42213e0fb3a479475c06e280eb02ef7b001a355d1600';
  assert.equal(machineCid(body), cid);
  for (const law of body.law_ids) assert.ok(loadRegistry().body.law_ids.includes(law));
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const owner = family.documents.find(d => d.spec_id === 'actql.protocol.contracts');
  assert.deepEqual(owner.machine_contracts.filter(ref => ref.path === path), [{path,pointer:'',cid,version:body.version}]);
  const implementation = readFileSync(new URL('../src/pipeline_check_context/core_contracts.mbt', import.meta.url), 'utf8');
  assert.ok(implementation.replace(/\s+/g, ' ').includes(`JoinCountRules => "${cid}"`));
});

test('independent join bound vectors cover outer emptiness and conditional uniqueness', () => {
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/bound-join.json', import.meta.url), 'utf8'));
  assert.equal(corpus.version, 'actql-bound-join-vectors/0.1');
  for (const v of corpus.cases) {
    const l = BigInt(v.left), r = BigInt(v.right);
    const lu = v.unique === 'left' || v.unique === 'both';
    const ru = v.unique === 'right' || v.unique === 'both';
    let n;
    if ((lu || ru) && l > 0n && r > 0n && v.kind !== 'asof') {
      switch (v.kind) {
        case 'inner': n = lu && ru ? (l < r ? l : r) : ru ? l : r; break;
        case 'left': n = ru ? l : l + r - 1n; break;
        case 'full': n = l + r; break;
        case 'semi': case 'anti': n = l; break;
        default: assert.fail(v.kind);
      }
    } else {
      switch (v.kind) {
        case 'inner': n = l * r; break;
        case 'left': n = l * (r || 1n); break;
        case 'full': n = l === 0n ? r : r === 0n ? l : l === 1n || r === 1n ? l + r : l * r; break;
        case 'semi': n = r === 0n ? 0n : l; break;
        case 'anti': case 'asof': n = l; break;
        default: assert.fail(v.kind);
      }
    }
    if (n > 9007199254740991n) assert.equal(v.error, 'Overflow');
    else { assert.equal(v.error, undefined); assert.equal(n, BigInt(v.expected)); }
  }
});

test('join bounds dominate every small matching relation including unmatched rows', () => {
  // Enumerate match incidence, not a product join implementation. Vertices are
  // row occurrences, so identical values do not erase multiplicity.
  for (let l = 0; l <= 3; l++) for (let r = 0; r <= 3; r++) {
    for (let mask = 0; mask < 2 ** (l * r); mask++) {
      const left = Array(l).fill(0), right = Array(r).fill(0);
      let matches = 0;
      for (let i = 0; i < l; i++) for (let j = 0; j < r; j++) {
        if (mask & (1 << (i * r + j))) { left[i]++; right[j]++; matches++; }
      }
      const missingLeft = left.filter(n => n === 0).length;
      const missingRight = right.filter(n => n === 0).length;
      const actual = {inner:matches, left:matches + missingLeft,
        full:matches + missingLeft + missingRight, semi:l - missingLeft, anti:missingLeft};
      const bounds = {inner:l*r, left:l*Math.max(1,r),
        full:l === 0 ? r : r === 0 ? l : l === 1 || r === 1 ? l+r : l*r,
        semi:r === 0 ? 0 : l, anti:l};
      for (const kind of Object.keys(actual)) assert.ok(actual[kind] <= bounds[kind]);
      // Unique left keys mean at most one matching left occurrence per right.
      const lu = right.every(n => n <= 1), ru = left.every(n => n <= 1);
      if (l && r && (lu || ru)) {
        assert.ok(actual.inner <= (lu && ru ? Math.min(l,r) : ru ? l : r));
        assert.ok(actual.left <= (ru ? l : l+r-1));
        assert.ok(actual.full <= l+r);
      }
    }
  }
});

test('common Relation count semantics have a registered body distinct from classification', () => {
  const path = 'spec/contracts/actql-bound-relation-laws.json';
  const body = JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
  const cid = 'sha256:163a0d75d56310803ac755d5f4f02069f442651711209037d6e3f512954c97ab';
  assert.equal(machineCid(body), cid);
  assert.deepEqual(Object.keys(body).sort(), ['application','arithmetic','conditionality','rules','scope','unit','version']);
  assert.equal(body.unit, 'rows');
  assert.deepEqual(Object.keys(body.rules).sort(), ['append','global_group','preserve','take_top_k','unnest','unpivot']);
  for (const rule of Object.values(body.rules)) {
    for (const law of rule.law_ids ?? (rule.law_id ? [rule.law_id] : [])) assert.ok(loadRegistry().body.law_ids.includes(law));
  }
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const owner = family.documents.find(d => d.spec_id === 'actql.protocol.contracts');
  assert.deepEqual(owner.machine_contracts.filter(ref => ref.path === path), [{path,pointer:'',cid,version:body.version}]);
  const implementation = readFileSync(new URL('../src/pipeline_check_context/core_contracts.mbt', import.meta.url), 'utf8');
  assert.ok(implementation.replace(/\s+/g, ' ').includes(`RelationCountRules => "${cid}"`));
});

test('independent common Relation count vectors preserve multiplicity and reject overflow', () => {
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/bound-relation.json', import.meta.url), 'utf8'));
  assert.equal(corpus.version, 'actql-bound-relation-vectors/0.1');
  const safe = value => { assert.ok(Number.isSafeInteger(value) && value >= 0); return BigInt(value); };
  for (const v of corpus.cases) {
    const inputs = v.inputs.map(safe);
    if (v.rule === 'unnest' && v.max_items === null) { assert.equal(v.error,'Unresolved'); continue; }
    let n;
    switch(v.rule) {
      case 'preserve': n = inputs[0]; break;
      case 'global_group': n = 1n; break;
      case 'clamp': { const k = safe(v.factor); n = inputs.length ? (inputs[0] < k ? inputs[0] : k) : k; break; }
      case 'append': n = inputs[0] + inputs[1]; break;
      case 'multiply': n = inputs[0] * safe(v.factor); break;
      case 'unnest': n = inputs[0] * safe(v.outer ? Math.max(1,v.max_items) : v.max_items); break;
      default: assert.fail(`unknown rule ${v.rule}`);
    }
    if(n > 9007199254740991n) assert.equal(v.error,'Overflow',v.name);
    else { assert.equal(v.error,undefined,v.name); assert.equal(n,safe(v.expected),v.name); }
  }
});

test('compiler selects the registered bound transfer classification body', () => {
  const path = 'spec/contracts/actql-bound-transfer-laws.json';
  const body = JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
  const cid = 'sha256:014682262d00c8435f300731e823e5b267ec66b78f980c765c4fd3772c68c911';
  assert.equal(machineCid(body), cid);
  assert.deepEqual(Object.keys(body).sort(), ['operations', 'version']);
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const references = family.documents.flatMap(document => document.machine_contracts ?? []).filter(ref => ref.path === path);
  assert.ok(references.length > 0);
  for (const ref of references) assert.deepEqual(ref, {path, pointer: '', cid, version: body.version});
  const implementation = readFileSync(new URL('../src/pipeline_check_context/core_contracts.mbt', import.meta.url), 'utf8');
  assert.ok(implementation.replace(/\s+/g, ' ').includes(`BoundTransferRules => "${cid}"`));
});

test('values count law has a separately pinned semantic body', () => {
  const path = 'spec/contracts/actql-bound-values-law.json';
  const body = JSON.parse(readFileSync(new URL(`../${path}`, import.meta.url), 'utf8'));
  const cid = 'sha256:0e0f9b4b6585ab7b17bafe484e82f44cd8f3acc9eec5ef9329cea200237a7971';
  assert.equal(machineCid(body), cid);
  assert.equal(body.law_id, 'actql.bound.values');
  assert.equal(body.unit, 'rows');
  assert.ok(loadRegistry().body.law_ids.includes(body.law_id));
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const owner = family.documents.find(document => document.spec_id === 'actql.protocol.contracts');
  assert.deepEqual(owner.machine_contracts.filter(ref => ref.path === path), [{
    path, pointer: '', cid, version: 'actql-bound-values-law/0.1',
  }]);
  assert.notEqual(machineCid(loadRegistry().body), cid);
  const implementation = readFileSync(new URL('../src/pipeline_check_context/core_contracts.mbt', import.meta.url), 'utf8');
  assert.ok(implementation.replace(/\s+/g, ' ').includes(`ValuesCountLaw => "${cid}"`), 'stale compiler law body pin');
});

test('independent values count vectors count row occurrences, not cell contents', () => {
  const corpus = JSON.parse(readFileSync(new URL('../portability/corpus/bound-values.json', import.meta.url), 'utf8'));
  assert.equal(corpus.version, 'actql-bound-values-vectors/0.1');
  // This is only the authored row shape/count oracle. It does not bind or
  // validate cells, and a known count does not authorize execution.
  function count(rows) {
    assert.ok(Array.isArray(rows));
    let result = 0;
    for (const row of rows) {
      assert.ok(row !== null && typeof row === 'object' && !Array.isArray(row));
      result += 1;
    }
    return result;
  }
  for (const vector of corpus.cases) {
    assert.equal(count(vector.rows), vector.expected_rows, vector.name);
  }
  for (const rows of corpus.rejections) assert.throws(() => count(rows));
});

test('registry fixes its identity, rejects missing Host entries and malformed names', () => {
  const { body, policy } = loadRegistry();
  assert.equal(validateRegistry(body, policy), 'sha256:45f824fa077ac7eb6fecda6e25fa954834f1854c512f99f6803ad2ab84dd899a');
  assert.ok(body.law_ids.includes('actql.bound.text-rank'));
  for (const name of ['values', 'time-series', 'calendar-series']) {
    assert.ok(body.law_ids.includes(`actql.bound.${name}`));
  }
  const family = JSON.parse(readFileSync(new URL('../spec/spec-family.json', import.meta.url), 'utf8'));
  const owner = family.documents.find(document => document.spec_id === 'actql.protocol.contracts');
  assert.deepEqual(owner.machine_contracts.filter(ref => ref.path === 'spec/contracts/actql-bound-law-registry.json'), [{
    path: 'spec/contracts/actql-bound-law-registry.json', pointer: '',
    cid: validateRegistry(body, policy), version: body.version,
  }]);
  for (const mutate of [
    value => { value.version = 'actql-bound-law-registry/1.0'; },
    value => { value.law_ids = []; },
    value => { value.law_ids.push(value.law_ids[0]); },
    value => { value.law_ids.reverse(); },
    value => { value.law_ids = value.law_ids.filter(id => id !== 'actql.host.relation-output'); },
    value => { value.law_ids[0] = ' actql.bound.append'; },
    value => { value.extra = true; },
    value => { delete value.author_guard_laws.nest; },
    value => { value.author_guard_laws.nest.unit = 'nodes'; },
    value => { value.author_guard_laws.nest.law_id = 'actql.bound.take'; },
    value => { value.author_guard_laws.nest.field = 'max_hops'; },
  ]) {
    const variant = structuredClone(body);
    mutate(variant);
    assert.throws(() => validateRegistry(variant, policy));
  }
  const generated = renderRegistry(body);
  for (const id of body.law_ids) assert.ok(generated.includes(`${JSON.stringify(id)} => Some(RegisteredLaw(law))`));
});

test('author guard source mappings preserve scope units and registered laws', () => {
  const {body} = loadRegistry();
  const expected = {
    join:['max_output_rows','rows','actql.guard.join-output'],
    cross_join:['max_output_rows','rows','actql.guard.join-output'],
    interval_join:['max_output_rows','rows','actql.guard.join-output'],
    nest:['max_items','array_items','actql.guard.nested-array-items'],
    array_agg:['max_items','array_items','actql.guard.array-aggregate'],
    string_agg:['max_bytes','bytes','actql.guard.string-aggregate'],
    sequence_matches:['max_matches_per_key','matches_per_key','actql.guard.sequence-matches'],
    sequence_output:['max_output_rows','rows','actql.guard.sequence-output'],
    components:['max_output_rows','rows','actql.guard.components-output'],
    traverse:['max_output_rows','rows','actql.guard.traverse-output'],
    shortest_path:['max_output_rows','rows','actql.guard.shortest-output'],
  };
  assert.deepEqual(Object.fromEntries(Object.entries(body.author_guard_laws).map(([scope,rule]) =>
    [scope,[rule.field,rule.unit,rule.law_id]])),expected);
  assert.ok(!body.law_ids.includes('actql.expression-fragment.capacity'));
  assert.equal(readFileSync(new URL('../src/pipeline_typing/guard_laws.generated.mbt',import.meta.url),'utf8'),renderGuardLaws(body));
});
