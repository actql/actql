// These explicit ABI doubles verify private callback/membership/lifetime glue.
// Actual typed values and vendor semantics require the matching Common caller.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createNotionOriginalEffectPropertyCodec} from '../host/original-effect-property-codec.mjs';

const ok = value => ({$tag: 1, _0: value});
function fixture({maxRows = 2, maxProperties = 2, assertCurrent} = {}) {
  const catalog = Object.freeze({}), calls = [], retired = new Set();
  let current = true;
  const options = {
    rowLimits: {maxRows, maxFields: 4, maxWork: 1000, maxNodes: 30, maxDepth: 8, maxTextBytes: 1000},
    writeLimits: {maxBytes: 4096, maxNodes: 100, maxDepth: 8, maxProperties,
      maxItems: 100, maxTextUnits: 1000, maxWork: 10000},
    assertCurrent: assertCurrent ?? function () {
      assert.equal(this, options);
      if (!current) throw new Error('OriginalCurrentRevoked');
    },
  };
  const moon = {
    clientProgramNotionPropertyWriteLimits(...values) { calls.push(['limits', this, ...values]); return Object.freeze({values}); },
    clientProgramEffectCheckedProposalRow(plan, exported, original, ...limits) {
      calls.push(['project', this, plan, exported, original, ...limits]);
      return ok(Object.freeze({plan, exported, original}));
    },
    clientProgramEffectCheckedProposalRowAvailable(row) { assert.equal(this, moon); return !retired.has(row); },
    clientProgramEffectCheckedProposalRowRetire(row) { assert.equal(this, moon); calls.push(['retire', row]); retired.add(row); },
    clientProgramEffectNotionPropertyWrite(row, field, originalCatalog, property, limits) {
      calls.push(['property', this, row, field, originalCatalog, property, limits]);
      return ok(Object.freeze({row, field, catalog: originalCatalog, property}));
    },
    clientProgramEffectNotionDateRangeWrite(row, start, end, originalCatalog, property, limits) {
      calls.push(['range', this, row, start, end, originalCatalog, property, limits]);
      return ok(Object.freeze({row, field: start, end, catalog: originalCatalog, property}));
    },
    clientProgramEffectNotionWritesJson(row, originalCatalog, values) {
      assert.equal(this, moon);
      assert(values.every(value => value.row === row && value.catalog === originalCatalog));
      calls.push(['wire', row, originalCatalog, values]);
      return ok('original-codec-wire');
    },
  };
  const view = createNotionOriginalEffectPropertyCodec(moon, catalog, options);
  return {moon, catalog, options, calls, view,
    revoke() { current = false; }, restore() { current = true; }};
}

test('Notion original codec captures methods and receiver and preserves exact row property and date-pair arguments', () => {
  const f = fixture();
  for (const name of Object.keys(f.moon)) f.moon[name] = () => assert.fail('Replaced callback');
  const plan = Object.freeze({}), exported = Object.freeze({}), original = Object.freeze({});
  const row = f.view.projectRow(plan, exported, original);
  const single = f.view.property(row, 0, 3), range = f.view.dateRange(row, 1, 2, 4);
  assert.equal(f.view.wire(row, [single, range]), 'original-codec-wire');
  const project = f.calls.find(call => call[0] === 'project');
  assert.equal(project[1], f.moon); assert.equal(project[2], plan);
  assert.equal(project[3], exported); assert.equal(project[4], original);
  const property = f.calls.find(call => call[0] === 'property');
  assert.equal(property[1], f.moon); assert.equal(property[3], 0);
  assert.equal(property[4], f.catalog); assert.equal(property[5], 3);
  const paired = f.calls.find(call => call[0] === 'range');
  assert.equal(paired[3], 1); assert.equal(paired[4], 2);
  assert.equal(paired[5], f.catalog); assert.equal(paired[6], 4);
  f.view.retireRow(row);
  assert.throws(() => f.view.wire(row, [single]), {code: 'UnavailableNotionEffectRow'});
  assert.equal(f.calls.filter(call => call[0] === 'retire').length, 1);
  f.view.retire();
});

test('Notion original codec refuses copied foreign row and write handles before wire encoding', () => {
  const f = fixture(), other = fixture();
  const row = f.view.projectRow({}, {}, {}), foreignRow = other.view.projectRow({}, {}, {});
  const write = f.view.property(row, 0, 0), foreignWrite = other.view.property(foreignRow, 0, 0);
  for (const selected of [[{...write}], [foreignWrite]]) {
    assert.throws(() => f.view.wire(row, selected), {code: 'ForeignNotionEffectWrite'});
  }
  assert.throws(() => f.view.property({...row}, 0, 0), {code: 'UnavailableNotionEffectRow'});
  assert.throws(() => f.view.property(foreignRow, 0, 0), {code: 'UnavailableNotionEffectRow'});
  assert.equal(f.calls.filter(call => call[0] === 'wire').length, 0);
  f.view.retire(); other.view.retire();
});

test('Notion original codec holds independent row and property limits before adding aliases', () => {
  const zero = fixture({maxRows: 0});
  assert.throws(() => zero.view.projectRow({}, {}, {}), {code: 'NotionEffectRowLimit'});
  assert.equal(zero.calls.filter(call => call[0] === 'project').length, 0);
  const f = fixture({maxRows: 1, maxProperties: 1}), row = f.view.projectRow({}, {}, {});
  f.view.property(row, 0, 0);
  assert.throws(() => f.view.property(row, 1, 1), {code: 'NotionEffectPropertyLimit'});
  f.view.retireRow(row);
  assert.throws(() => f.view.projectRow({}, {}, {}), {code: 'NotionEffectRowLimit'});
  assert.equal(f.calls.filter(call => call[0] === 'property').length, 1);
  zero.view.retire(); f.view.retire();
});

test('Notion original codec never revives current failure and still retires original DATA aliases', () => {
  const f = fixture(), row = f.view.projectRow({}, {}, {}), write = f.view.property(row, 0, 0);
  f.revoke();
  assert.throws(() => f.view.wire(row, [write]), /OriginalCurrentRevoked/u);
  f.restore();
  assert.throws(() => f.view.wire(row, [write]), /OriginalCurrentRevoked/u);
  assert.equal(f.calls.filter(call => call[0] === 'wire').length, 0);
  f.view.retire();
  assert.equal(f.calls.filter(call => call[0] === 'retire').length, 1);
  assert.throws(() => f.view.projectRow({}, {}, {}), {code: 'NotionEffectCodecRetired'});
});

test('Notion original codec rejects inherited or accessor ports without invoking them and rejects async fences', () => {
  const f = fixture(); let getters = 0;
  const accessor = {...f.moon};
  Object.defineProperty(accessor, 'clientProgramEffectNotionPropertyWrite', {get() { getters++; return () => {}; }});
  assert.throws(() => createNotionOriginalEffectPropertyCodec(accessor, f.catalog, f.options),
    {code: 'NotionEffectCodecRuntimeUnavailable'});
  assert.equal(getters, 0);
  assert.throws(() => createNotionOriginalEffectPropertyCodec(Object.create(f.moon), f.catalog, f.options),
    {code: 'NotionEffectCodecRuntimeUnavailable'});
  assert.throws(() => fixture({assertCurrent: () => Promise.resolve()}),
    {code: 'InvalidNotionEffectCodecCurrentFence'});
  f.view.retire();
});
