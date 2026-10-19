// Actual Common Captured/Mapping/managed Result and existing Notion codec.
// Fixture policy/catalogue selection is not an installed target or write grant.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checked} from '../../../host-common/runtime-result.mjs';
import {exportPinnedEffectLocalResult} from '../../../host-node/effect-input-export.mjs';
import {createNotionOriginalEffectPropertyCodec} from '../host/original-effect-property-codec.mjs';
import {moon, originalNotionCatalog, originalNotionEffectValuesFixture,
  propertyWriteLimits, originalRowLimits, writeLimits} from './original-effect-values.fixture.mjs';

const begin = f => checked(moon.clientProgramEffectProposalBegin(f.inputs, 0, 10, 100000));
const projected = (plan, exported, original) => checked(moon.clientProgramEffectCheckedProposalRow(
  plan, exported, original, 10, 100000, 100, 16, 1000));

test('actual original Captured values encode exact Notion Decimal and nullable Date pairs without JSON re-admission', async () => {
  const f = await originalNotionEffectValuesFixture(), catalog = originalNotionCatalog();
  const view = createNotionOriginalEffectPropertyCodec(moon, catalog, {
    rowLimits: originalRowLimits, writeLimits: propertyWriteLimits, assertCurrent() {},
  });
  const plan = begin(f), wires = [], chunks = [], escaped = [];
  try {
    const result = await exportPinnedEffectLocalResult({...f, onChunk: chunk => { chunks.push(chunk); },
      onOriginalRow(index, original, exported) {
        const row = view.projectRow(plan, exported, original);
        // Target fields have canonical Mapping order, independent of selected
        // Result order and the unrelated vendor display labels.
        const amount = view.property(row, 0, 0), period = view.dateRange(row, 3, 1, 1);
        assert.throws(() => view.property(row, 2, 1), {code: 'MoonBitHostFailure'},
          'a Text spelling of a Date is not the original checked Date');
        wires.push(view.wire(row, [amount, period])); escaped.push({row, amount});
        assert.equal(index, wires.length - 1);
      }});
    checked(moon.clientProgramEffectProposalFinish(plan, result.rowCount));
    assert.equal(result.rowCount, 2);
    // Compare full bytes: JSON.parse would round the vendor numeric literal.
    assert.deepEqual(wires, [
      '{"properties":{"amount%3Aid":{"number":9007199254740993.25},"date%3Aid":{"date":{"start":"2024-02-29","end":null}}}}',
      '{"properties":{"amount%3Aid":{"number":-9007199254740993.25},"date%3Aid":{"date":{"start":"2024-03-01","end":"2024-03-02"}}}}',
    ]);
    assert.equal(JSON.parse(chunks.join(''))[0].amount, '9007199254740993.25');
    for (const {row, amount} of escaped) {
      assert.throws(() => view.wire(row, [amount]), {code: 'UnavailableNotionEffectRow'});
    }
  } finally { view.retire(); moon.clientProgramEffectProposalCancel(plan); await f.close(); }
});

test('actual Notion typed write rejects equal foreign Catalog and another original Mapping-row projection', async () => {
  const f = await originalNotionEffectValuesFixture(), catalog = originalNotionCatalog(), foreign = originalNotionCatalog();
  const plan = begin(f), otherPlan = begin(f), bounds = writeLimits();
  try {
    const result = await exportPinnedEffectLocalResult({...f, onChunk() {},
      onOriginalRow(index, original, exported) {
        const row = projected(plan, exported, original), other = projected(otherPlan, exported, original);
        try {
          const write = checked(moon.clientProgramEffectNotionPropertyWrite(row, 0, catalog, 0, bounds));
          assert.throws(() => checked(moon.clientProgramEffectNotionWritesJson(row, foreign, [write], bounds)),
            {code: 'MoonBitHostFailure'});
          assert.throws(() => checked(moon.clientProgramEffectNotionWritesJson(other, catalog, [write], bounds)),
            {code: 'MoonBitHostFailure'});
          assert.throws(() => checked(moon.clientProgramEffectNotionWritesJson(row, catalog, [write, write], bounds)),
            {code: 'MoonBitHostFailure'});
          assert.match(checked(moon.clientProgramEffectNotionWritesJson(row, catalog, [write], bounds)),
            /"number":-?9007199254740993\.25/u);
          assert.equal(index < 2, true);
        } finally {
          moon.clientProgramEffectCheckedProposalRowRetire(row);
          moon.clientProgramEffectCheckedProposalRowRetire(other);
        }
      }});
    checked(moon.clientProgramEffectProposalFinish(plan, result.rowCount));
    checked(moon.clientProgramEffectProposalFinish(otherPlan, result.rowCount));
  } finally {
    moon.clientProgramEffectProposalCancel(plan); moon.clientProgramEffectProposalCancel(otherPlan); await f.close();
  }
});

test('actual original Effect exporter refuses retired pins after awaited consumer before any row publication', async () => {
  const f = await originalNotionEffectValuesFixture(); let delivered = 0, chunks = 0;
  try {
    await assert.rejects(exportPinnedEffectLocalResult({...f,
      async onOriginalRow() { delivered++; await Promise.resolve(); moon.clientProgramReleaseEffectInputs(f.inputs); },
      onChunk() { chunks++; }}), /UnavailableEffectOriginalRow/u);
    assert.equal(delivered, 1); assert.equal(chunks, 0);
  } finally { await f.close(); }
});
