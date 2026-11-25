// Explicit ABI doubles isolate callback/retirement glue. These are not actual
// Common, vendor I/O, original FD cleanup or installed Source acceptance.
import assert from 'node:assert/strict';
import test from 'node:test';
import {exportPinnedEffectInput, exportPinnedEffectLocalResult} from './effect-source-stream.mjs';
import {runtimePair, runtimeTriple} from '../host-common/compiler-binding.generated.mjs';

type ExportOptions = Parameters<typeof exportPinnedEffectLocalResult>[0];
const ok = <Value,>(value: Value) => ({$tag: 1, _0: value});
function fixture() {
  const original = {}, exported = {}, calls: string[] = [];
  let available = true, next = 0;
  const moon = {
    clientProgramEffectLocalResultAt: () => ({}),
    clientProgramEffectLocalResultTask: () => 0,
    clientProgramEffectLocalResultExportStart() { calls.push('start'); return ok(exported); },
    clientProgramEffectLocalResultExportPreparation: () => ({}),
    clientProgramEffectInputExportAdvance: () => ok(runtimePair(true, 1)),
    clientProgramEffectInputExportReady: () => ok({}),
    clientProgramEffectInputExportNextOriginalRow() {
      assert.equal(this, moon); calls.push('next');
      return ok(next++ === 0 ? runtimeTriple(0, '[{"id":1}', original) : undefined);
    },
    clientProgramEffectOriginalRowAvailable(inputs: unknown, actualExport: unknown, value: unknown) {
      assert.equal(this, moon); assert.equal(actualExport, exported);
      assert.equal(inputs, options.inputs); assert.equal(value, original); return available;
    },
    clientProgramEffectOriginalRowRetire(value: unknown) {
      assert.equal(this, moon); assert.equal(value, original); calls.push('retire'); available = false;
    },
    clientProgramEffectInputExportFinish() { calls.push('finish'); return ok(runtimePair({}, ']')); },
    clientProgramEffectLocalResultExportMatchesReceipt: () => true,
    clientProgramEffectInputExportFields: () => ['id'],
    clientProgramEffectInputExportLogicalCid: () => 'logical',
    clientProgramEffectInputExportSchemaCid: () => 'schema',
    clientProgramEffectInputExportRowCount: () => 1,
    clientProgramEffectInputExportReleaseReceipt() { calls.push('receipt-release'); },
    clientProgramEffectInputExportCancel() { calls.push('cancel'); },
    clientProgramEffectInputExportCancelPreparation() { calls.push('cancel-preparation'); },
  };
  // This double implements only the selected Local Result ABI.
  const options = {moon: moon as unknown as ExportOptions['moon'], execution: {effectPhysicalSource(): undefined {}}, inputs: {}, resultIndex: 0, limits: {},
    originalRowLimits: {maxNodes: 100, maxDepth: 8, maxUtf16Units: 4096}};
  return {moon, original, exported, calls, revoke() { available = false; }, options};
}

test('original Effect row exporter captures runtime callbacks and delivers its exact export and row once', async () => {
  const f = fixture(), chunks: string[] = [], rows: [number, unknown, unknown][] = [];
  const result = await exportPinnedEffectLocalResult({...f.options,
    async onOriginalRow(index, row, exported) {
      rows.push([index, row, exported]);
      f.moon.clientProgramEffectOriginalRowAvailable = () => assert.fail('Replacement availability');
      f.moon.clientProgramEffectOriginalRowRetire = () => assert.fail('Replacement retirement');
      f.moon.clientProgramEffectInputExportNextOriginalRow = () => assert.fail('Replacement reader');
      await Promise.resolve();
    }, onChunk: chunk => { chunks.push(chunk); }});
  assert.deepEqual(rows, [[0, f.original, f.exported]]);
  assert.equal(chunks.join(''), '[{"id":1}]'); assert.equal(result.rowCount, 1);
  assert.deepEqual(f.calls, ['start', 'next', 'retire', 'next', 'finish', 'receipt-release', 'cancel']);
});

test('original Effect row exporter rechecks current after awaited consumer before publishing bytes', async () => {
  const f = fixture(); let chunks = 0;
  await assert.rejects(exportPinnedEffectLocalResult({...f.options,
    async onOriginalRow() { await Promise.resolve(); f.revoke(); },
    onChunk() { chunks++; }}), /UnavailableEffectOriginalRow/u);
  assert.equal(chunks, 0);
  assert.deepEqual(f.calls, ['start', 'next', 'retire', 'cancel']);
});

test('original Effect row exporter preserves abort and retires without advancing or finalizing', async () => {
  const f = fixture(), controller = new AbortController(); let chunks = 0;
  await assert.rejects(exportPinnedEffectLocalResult({...f.options, signal: controller.signal,
    async onOriginalRow() { await Promise.resolve(); controller.abort(new Error('StopOriginal')); },
    onChunk() { chunks++; }}), /StopOriginal/u);
  assert.equal(chunks, 0);
  assert.deepEqual(f.calls, ['start', 'next', 'retire', 'cancel']);
});

test('original Effect row exporter refuses incompatible paths and accessor runtime before acquisition', async () => {
  const f = fixture(), options = {...f.options, onOriginalRow() {}, onChunk() {}};
  // Exercise the JavaScript caller that selects an incompatible row path.
  await assert.rejects(exportPinnedEffectInput(options as unknown as Parameters<typeof exportPinnedEffectInput>[0]), /InvalidEffectInputExport/u);
  await assert.rejects(exportPinnedEffectLocalResult({...options, onCanonicalRow() {}}), /InvalidEffectInputExport/u);
  let getters = 0;
  Object.defineProperty(f.moon, 'clientProgramEffectOriginalRowRetire', {get() { getters++; return () => {}; }});
  await assert.rejects(exportPinnedEffectLocalResult(options), /OriginalEffectRowRuntimeUnavailable/u);
  assert.equal(getters, 0); assert.deepEqual(f.calls, []);
});
