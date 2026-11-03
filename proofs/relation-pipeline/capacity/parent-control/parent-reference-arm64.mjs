// Restricted correspondence for the pinned Darwin ARM64 debug constructor.
// Private frame custody and exact helper bodies are checked, not inferred from
// GC scalar descriptors. This is not a general machine-code or lifetime proof.
import assert from 'node:assert/strict';
import {codeSymbols} from './provider-callback-code.mjs';

export const arm64ReferenceHelpers = ['__M0MPC13ref3Ref3RefGlE', '__M0MPC13ref3Ref3RefGbE', '__M0MPC13ref3Ref3RefGiE'];
const observer = '_actql_proof_current_chain_start';
const roles = ['used', 'cancelled', 'terminal', 'reclaimed', 'cleanupIndex'];
const helpers = [arm64ReferenceHelpers[0], ...Array(3).fill(arm64ReferenceHelpers[1]), arm64ReferenceHelpers[2]];
const parentName = name => /connectors5local[0-9]+bounded__relation__chain__execution__state$/.test(name);
const ownerName = name => /connectors5local[0-9]+managed__provider__execution__with__child__work__issue$/.test(name);
const reclaimedPrefixName = name => /connectors5local[0-9]+relation__chain__reclaimed__prefix$/.test(name);

export function arm64Functions(text) {
  const result = new Map(); let current;
  for (const line of text.split('\n')) {
    const fn = line.match(/^([0-9a-f]+) <([^>]+)>:$/);
    if (fn) {
      assert(!result.has(fn[2]), 'Duplicate inspected ARM64 function');
      current = {start: BigInt('0x' + fn[1]), instructions: []}; result.set(fn[2], current); continue;
    }
    const reloc = line.match(/^\s*([0-9a-f]+):\s+ARM64_RELOC_(BRANCH26|PAGE21|PAGEOFF12)\s+(\S+)$/);
    if (reloc) {
      const ins = current?.instructions.at(-1);
      assert(ins && ins.address === BigInt('0x' + reloc[1]) && !ins.relocation, 'Detached or duplicate ARM64 relocation');
      ins.relocation = {kind: reloc[2], symbol: reloc[3]}; continue;
    }
    assert(!line.includes('ARM64_RELOC_'), 'Unsupported ARM64 relocation');
    const m = line.match(/^\s*([0-9a-f]+):\s+([a-z][a-z0-9.]*)\s*(.*)$/);
    if (!m) continue;
    assert(current, 'ARM64 instruction outside function');
    const address = BigInt('0x' + m[1]), last = current.instructions.at(-1);
    assert(!last || address === last.address + 4n, 'Noncontiguous ARM64 instructions');
    current.instructions.push({address, op: `${m[2]} ${m[3].split(';')[0].split(' <')[0].trim()}`.trim().replace(/\s+/g, ' ').replace(/,\s*/g, ', ')});
  }
  return result;
}
export function arm64CallTarget(ins, symbols) {
  if (!ins?.op.startsWith('bl ')) return;
  if (ins.relocation) { assert.equal(ins.relocation.kind, 'BRANCH26', 'Wrong ARM64 call relocation'); return ins.relocation.symbol; }
  const m = ins.op.match(/^bl (0x[0-9a-f]+)$/);
  if (!m || !symbols) return;
  const matches = [...symbols].filter(([, address]) => address === BigInt(m[1])).map(([name]) => name);
  assert(matches.length <= 1, 'Ambiguous ARM64 executed call'); return matches[0];
}
const callTarget = arm64CallTarget;
function extent(name, fn, symbols) {
  assert(fn, 'Missing executed ARM64 Ref helper');
  const wide = name === arm64ReferenceHelpers[0], payload = wide ? 8 : 4;
  const expected = ['sub sp, sp, #0x20', 'stp x29, x30, [sp, #0x10]', 'add x29, sp, #0x20',
    'stur x19, [x29, #-0x18]', wide ? 'mov x19, x0' : 'mov w19, w0',
    `mov x0, #0x${payload}`, 'bl _moonbit_malloc', 'mov w10, #0x0', 'stur w10, [x0, #-0x4]',
    wide ? 'str x19, [x0]' : 'str w19, [x0]', 'ldur x19, [x29, #-0x18]',
    'ldp x29, x30, [sp, #0x10]', 'add sp, sp, #0x20', 'ret'];
  const actual = fn.instructions.filter(i => i.op !== 'nop').map(i => i.op.startsWith('bl ') ? `bl ${callTarget(i, symbols)}` : i.op);
  assert.deepEqual(actual, expected, 'Unreviewed ARM64 primitive Ref allocation/return sequence');
  return {helper: name, payloadBytes: payload, headerBytes: 8, requestedBytes: payload + 8};
}
function frameWrite(op, frameBytes) {
  if (!/^(?:str|stur)/.test(op) || !/\[(?:x29|sp)(?:,|\])/.test(op)) return;
  const m = op.match(/^(str|stur)(b|h)? ([xw]\d+), \[(x29|sp)(?:, #(-?0x[0-9a-f]+))?\]$/);
  assert(m, 'Unreviewed ARM64 frame write');
  const width = m[2] === 'b' ? 1n : m[2] === 'h' ? 2n : m[3][0] === 'x' ? 8n : 4n;
  assert(!m[2] || m[3][0] === 'w', 'Invalid ARM64 narrow store');
  const offset = !m[5] ? 0n : m[5].startsWith('-') ? -BigInt(m[5].slice(1)) : BigInt(m[5]);
  return {start: offset - (m[4] === 'sp' ? frameBytes : 0n), width};
}
function privateFrame(op) {
  // Register copies, partial writes and frame-derived indexed addresses must
  // not expose or move the private caller frame. Only direct loads/stores use it.
  if (/^(?:ldr|ldur|str|stur)(?:b|h|sw)? /.test(op)) {
    assert(!/^(?:ldr|ldur)(?:b|h|sw)? (?:x29|w29|sp|wsp),/.test(op), 'ARM64 frame register replaced');
    assert(!/^(?:str|stur)(?:b|h)? (?:x29|w29|sp|wsp),/.test(op), 'ARM64 frame escapes through store');
    if (/\b(?:x29|w29|sp|wsp)\b/.test(op))
      assert(/\[(?:x29|sp)(?:, #-?0x[0-9a-f]+)?\]$/.test(op), 'ARM64 frame-derived address escapes');
  } else assert(!/\b(?:x29|w29|sp|wsp)\b/.test(op), 'ARM64 frame changes or escapes');
}
function callbackRetirement(ins, begin, end, symbols) {
  const releases = ins.flatMap((i, k) => k >= begin && k < end && callTarget(i, symbols) === '_moonbit_decref' ? [k] : []);
  if (!releases.length) return;
  const owners = ins.flatMap((i, k) => k >= begin && k < end && ownerName(callTarget(i, symbols) ?? '') ? [k] : []);
  assert.equal(owners.length, 1, 'Missing unique ARM64 retaining Owner handoff');
  const owner = owners[0], args = ins.slice(owner - 5, owner).map((i, n) => i.op.match(new RegExp(`^mov x${n}, (x(?:19|2[0-8]))$`))?.[1]);
  assert(args.every(Boolean) && new Set(args).size === 5, 'Changed ARM64 callback handoff roles');
  const allocation = (register, before) => {
    const number = register.slice(1), definition = ins.slice(begin, before).findLastIndex(i =>
      new RegExp(`^(?:mov|movk|ldr|ldur|add|adrp) [xw]${number},`).test(i.op));
    assert(definition >= 0, 'Missing ARM64 callback allocation alias');
    const k = begin + definition;
    assert.equal(ins[k].op, `mov ${register}, x0`, 'Changed ARM64 callback allocation alias');
    assert.equal(callTarget(ins[k - 1], symbols), '_moonbit_malloc', 'ARM64 retirement targets a primitive Ref or unknown allocation');
    return k;
  };
  const allocations = args.map(register => allocation(register, owner));
  assert.equal(releases.length, 5, 'Changed ARM64 callback retirement count');
  releases.forEach((k, n) => {
    assert(k > owner, 'ARM64 callback retirement precedes retaining handoff');
    assert.equal(ins[k - 1]?.op, `mov x0, ${args[n]}`, 'ARM64 retirement targets a Ref or substitutes callback roles');
    assert.equal(allocation(args[n], k), allocations[n], 'ARM64 callback identity changed after handoff');
  });
}
function sites(fn, symbols) {
  const ins = fn.instructions;
  const frame = ins[0]?.op.match(/^sub sp, sp, #(0x[0-9a-f]+)$/);
  assert(frame, 'Missing reviewed ARM64 private frame'); const frameBytes = BigInt(frame[1]);
  assert(frameBytes >= 32n && frameBytes % 16n === 0n, 'Invalid ARM64 frame extent');
  assert.equal(ins[1]?.op, `stp x29, x30, [sp, #0x${(frameBytes - 16n).toString(16)}]`, 'Changed ARM64 frame linkage');
  assert.equal(ins[2]?.op, `add x29, sp, #${frame[1]}`, 'Changed ARM64 frame base');
  const indices = ins.flatMap((i, k) => arm64ReferenceHelpers.includes(callTarget(i, symbols)) ? [k] : []);
  assert.equal(indices.length, 5, 'Changed ARM64 primitive Ref call count');
  const entries = indices.map((k, n) => {
    assert.equal(callTarget(ins[k], symbols), helpers[n], 'Changed ARM64 Ref type/order');
    const initial = n === 4 ? ['mov w0, #0xffff', 'movk w0, #0xffff, lsl #16'] : [n === 0 ? 'mov x0, #0x0' : 'mov w0, #0x0'];
    assert.deepEqual(ins.slice(k - initial.length, k).map(i => i.op), initial, 'Changed ARM64 Ref initializer');
    assert.equal(ins[k + 1]?.op, 'mov x16, x0', 'Lost ARM64 Ref return alias');
    const slot = ins[k + 2]?.op.match(/^stur x16, \[x29, #-(0x[0-9a-f]+)\]$/)?.[1];
    assert(slot, 'Missing ARM64 Ref custody slot'); const start = -BigInt(slot);
    assert(start <= -24n && start >= -frameBytes && start % 8n === 0n, 'Invalid ARM64 private custody slot');
    return {role: roles[n], helper: helpers[n], slot, start, storeIndex: k + 2, callOffset: (ins[k].address - fn.start).toString()};
  });
  assert.equal(new Set(entries.map(e => e.slot)).size, 5, 'ARM64 Ref custody slots alias');
  const probes = ins.flatMap((i, k) => callTarget(i, symbols) === observer ? [k] : []);
  assert.equal(probes.length, 1, 'Missing or repeated ARM64 observer'); const end = probes[0], begin = indices[0] - 1;
  assert(end > indices.at(-1), 'ARM64 observer precedes Ref construction');
  callbackRetirement(ins, begin, end, symbols);
  for (const i of ins.slice(3, begin)) privateFrame(i.op);
  for (let k = begin; k < end; k++) {
    const i = ins[k], op = i.op;
    assert(/^(?:mov |movk |ldr |ldur |str |stur |strb |sturb |strh |sturh |bl |adrp |add |cmp |b(?:\.ne)? |nop$)/.test(op), 'Unsupported ARM64 Ref custody instruction');
    privateFrame(op);
    const write = frameWrite(op, frameBytes);
    if (write) for (const e of entries) if (write.start < e.start + 8n && write.start + write.width > e.start)
      assert(k === e.storeIndex && write.start === e.start && write.width === 8n, 'ARM64 Ref custody overwritten');
    if (op.startsWith('bl ')) {
      const callee = callTarget(i, symbols);
      assert(helpers.includes(callee) || ['_moonbit_malloc', '_moonbit_incref', '_moonbit_decref'].includes(callee) || reclaimedPrefixName(callee ?? '') || ownerName(callee ?? ''), 'Unreviewed ARM64 custody call');
    }
    if (op.startsWith('b.ne ')) {
      const target = BigInt(op.slice(5)), skip = ins[k + 1]?.op.match(/^b (0x[0-9a-f]+)$/);
      assert(k > 0 && ins[k - 1].op === 'cmp x19, #0x0' && target === ins[k + 2]?.address && skip &&
        BigInt(skip[1]) === ins[k + 4]?.address && ins[k + 2]?.op === 'mov x0, x19' &&
        callTarget(ins[k + 3], symbols) === '_moonbit_incref', 'Unreviewed ARM64 conditional custody branch');
    } else if (op.startsWith('b ')) assert(ins[k - 1]?.op.startsWith('b.ne '), 'Unreviewed ARM64 custody branch');
  }
  for (const i of ins) {
    const branch = i.op.match(/^b(?:\.[a-z]+)? (0x[0-9a-f]+)$/);
    if (branch && BigInt(branch[1]) > ins[begin].address && BigInt(branch[1]) <= ins[end].address)
      assert(i.address >= ins[begin].address && i.address < ins[end].address, 'External ARM64 branch enters Ref custody');
    if (/^(?:cbz|cbnz|tbz|tbnz|br)\b/.test(i.op)) assert.fail('Unreviewed indirect ARM64 custody entry');
  }
  for (let n = 0; n < 5; n++)
    assert.equal(ins[end - 6 + n]?.op, `ldur x${n + 2}, [x29, #-${entries[n].slot}]`, 'ARM64 observer role substitution');
  return entries.map(({start, storeIndex, ...entry}) => entry);
}
export function inspectParentReferenceArm64(start, symbolText, objectText, linkedText) {
  const symbols = codeSymbols(symbolText), objects = arm64Functions(objectText), linked = arm64Functions(linkedText);
  const names = [...objects.keys()].filter(parentName); assert.equal(names.length, 1, 'Missing unique ARM64 parent');
  const name = names[0]; assert(linked.has(name), 'Missing executed ARM64 parent');
  const objectSites = sites(objects.get(name)), linkedSites = sites(linked.get(name), symbols);
  assert.deepEqual(linkedSites, objectSites, 'ARM64 object/executed Ref correspondence differs');
  const extents = new Map(arm64ReferenceHelpers.map(name => [name, extent(name, linked.get(name), symbols)]));
  const identities = new Set();
  const references = objectSites.map(site => {
    const identity = start.roots[site.role]; assert.match(identity, /^[1-9][0-9]*$/);
    assert(!identities.has(identity), 'Live ARM64 Ref identities alias'); identities.add(identity);
    return {identity, ...site, ...extents.get(site.helper)};
  });
  return {scope: 'five primitive Refs passed to the actual Darwin ARM64 parent constructor observer', constructor: name,
    structuralReferenceCount: 5, references, pointRequestedBytes: references.reduce((n, r) => n + r.requestedBytes, 0),
    payloadBytesMeasured: false, allocationRequestsEstablished: true, completePhysicalLifetimeUpper: false};
}
