// Actual public read fixtures reuse the existing named-assertion mutation guard.
// Import, timeout and unselected-test failures are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const acceptance = 'adapters/host-node/client-read-progress.test.mjs';
const shape = ['rows', 'all'].map(operation => ({
  name: `https: ${operation} refuses non-object delivery rows before yielding`,
  assertions: [{id: 'read-row-shape', operator: 'strictEqual'},
    {id: 'read-row-count', operator: 'strictEqual'}],
}));
const syntax = ['rows', 'all'].map(operation => ({
  name: `https: ${operation} classifies malformed JSON as an invalid delivery frame`,
  assertions: [{id: 'read-row-syntax', operator: 'strictEqual'},
    {id: 'read-row-count', operator: 'strictEqual'}],
}));
const lookupSnapshots = ['local', 'https'].map(entrance => ({
  name: `${entrance}: delivery lookup snapshots survive reused owner record containers`,
  assertions: ['snapshot', 'freeze', 'detached'].map(id => ({
    id: `delivery-lookup-${id}`, operator: 'strictEqual',
  })),
}));
const lookupAdmission = ['invalid field supplied at lookup boundary', 'lookup record cannot be captured']
  .map(fault => ({
    name: `local: delivery lookup rejects ${fault}`,
    assertions: [{id: 'delivery-lookup-admission', operator: 'strictEqual'}],
  }));
const lookupCapture = "            answer = captureResponse(answer);\n" +
  "            if (!validDeliveryAttemptLookup(answer, expected)) fail('InvalidHostAttemptLookup');\n";
const lookupCopy = "            const observation = answer;\n" +
  "            const observedKey = structuralKey(answer);\n" +
  "            answer = structuredClone(answer);\n" +
  "            if (!validDeliveryAttemptLookup(answer, expected) || structuralKey(answer) !== observedKey) fail('InvalidHostAttemptLookup');\n" +
  "            if (structuralKey(observation) !== observedKey) fail('InvalidHostAttemptLookup');\n" +
  "            return retainDeliveryExplanation(freezeInput(observation), {";
const observations = phase => ['local', 'https'].map(entrance => ({
  name: `${entrance}: delivery observation explains ${phase} against one published Run`,
  assertions: [{id: 'delivery-observation-classification', operator: 'strictEqual'},
    {id: 'delivery-opening-explanation', operator: 'strictEqual'},
    {id: 'delivery-observation-receipt', operator: 'strictEqual'},
    {id: 'delivery-observation-custody', operator: 'strictEqual'}],
}));
const observationAcceptance = 'adapters/host-node/client-delivery-observation.test.mjs';
const publishedRunAcceptance = 'adapters/host-node/client-read-run-capacity.test.mjs';
const publishedPrefixes = (consumers, id, operator) => ['local', 'https'].flatMap(entrance =>
  consumers.map(consumer => ({
    name: `${entrance}: actual 121-row Run preserves its interrupted ${consumer} attempt and permits an explicit new read after restart`,
    assertions: [{id, operator}],
  })));
const mutations = [
  ['an explicit reread silently starts another physical Compute', [
    ['const readExplanations = new WeakMap();',
      'const readExplanations = new WeakMap();\nconst unsafeReadRecomputations = new WeakSet();'],
    ['const readFailure = (cause, context, rowsYielded, prior) => {',
      'const readFailure = (cause, context, rowsYielded, prior) => {\n' +
      '  unsafeReadRecomputations.add(context.ref);'],
    ["          try {\n            const response = await runRequest('read', {",
      '          try {\n' +
      '            if (unsafeReadRecomputations.delete(ref)) {\n' +
      '              const original = submissionInputs.get(handle);\n' +
      '              if (original !== undefined) await submit(original.kind, original.input,\n' +
      '                {parameters: original.parameters});\n' +
      '            }\n' +
      "            const response = await runRequest('read', {"],
  ], ['local', 'https'].flatMap(entrance => ['rows', 'all'].map(consumer => ({
    name: `${entrance}: ${consumer} remains incomplete after all published rows when the terminator is lost`,
    assertions: [{id: 'read-reread-no-compute', operator: 'deepStrictEqual'}],
  }))), 'adapters/host-node/client-read-terminator.test.mjs'],
  ['a reordered reread skips the previous prefix without a resume contract', [
    ['const readExplanations = new WeakMap();',
      'const readExplanations = new WeakMap();\nconst unsafeReadOffsets = new WeakMap();'],
    ['const readFailure = (cause, context, rowsYielded, prior) => {',
      'const readFailure = (cause, context, rowsYielded, prior) => {\n' +
      '  const offsets = unsafeReadOffsets.get(context.ref) ?? new Map();\n' +
      '  offsets.set(context.resultName, Math.max(offsets.get(context.resultName) ?? 0, rowsYielded));\n' +
      '  unsafeReadOffsets.set(context.ref, offsets);'],
    ['        let rowsYielded = 0, rawRows = 0, retainedBytes = 0;',
      '        const unsafeOffset = unsafeReadOffsets.get(ref)?.get(name) ?? 0;\n' +
      '        let rowsYielded = 0, rawRows = 0, retainedBytes = 0;'],
    ['                const output = await acceptRow(row, size);\n' +
      '                controller.signal.throwIfAborted();\n' +
      '                rowsYielded++;\n                yield output;',
      '                const output = await acceptRow(row, size);\n' +
      '                controller.signal.throwIfAborted();\n' +
      '                if (rawRows <= unsafeOffset) continue;\n' +
      '                rowsYielded++;\n                yield output;'],
    ['                    rowsYielded++;\n                    yield output;',
      '                    if (rawRows <= unsafeOffset) continue;\n' +
      '                    rowsYielded++;\n                    yield output;'],
    ['                rowsYielded++;\n                yield output;\n              }\n              if (line',
      '                if (rawRows <= unsafeOffset) continue;\n' +
      '                rowsYielded++;\n                yield output;\n              }\n              if (line'],
  ], ['local', 'https'].flatMap(entrance => ['rows', 'all'].map(consumer => ({
    name: `${entrance}: explicit reordered ${consumer} reread never skips the previous prefix`,
    assertions: [{id: 'read-reordered-whole-value', operator: 'deepStrictEqual'}],
  }))), 'adapters/host-node/client-read-reorder.test.mjs'],
  ['an uncertain read opening silently creates another charged attempt', [
    ['    createDigest: installed.createDigest,\n    authorize,\n    signal,\n  });\n}',
      '    createDigest: installed.createDigest,\n    authorize,\n    signal,\n' +
      '  }).catch(cause => {\n' +
      "    if (input.attemptId.startsWith('unsafe-retry:')) throw cause;\n" +
      '    return deliverAuthorizedResult(service,\n' +
      "      {...input, attemptId: 'unsafe-retry:' + globalThis.crypto.randomUUID()}, sink);\n" +
      '  });\n}'],
  ], ['local', 'https'].map(entrance => ({
    name: `${entrance}: opening reply lost after-commit is looked up without reopening or consuming another grant`,
    assertions: [{id: 'read-opening-no-retry', operator: 'strictEqual'},
      {id: 'read-opening-no-retry', operator: 'deepStrictEqual'}],
  })), 'adapters/host-node/client-read-opening.test.mjs', 'adapters/host-common/result-access.mjs'],
  ['lost terminator is treated as a completed HTTPS read', [
    ["              if (line !== '\\x1e') fail('IncompleteResultStream');", ''],
  ], ['rows', 'all'].map(consumer => ({
    name: `https: ${consumer} remains incomplete after all published rows when the terminator is lost`,
    assertions: [{id: 'read-terminator-failure', operator: 'strictEqual'}],
  })), 'adapters/host-node/client-read-terminator.test.mjs'],
  ['lost terminator returns the buffered all value', [
    ['          throw readFailure(cause, readerContexts.get(reader), 0, readExplanations.get(cause));',
      '          return values;'],
  ], ['local', 'https'].map(entrance => ({
    name: `${entrance}: all remains incomplete after all published rows when the terminator is lost`,
    assertions: [{id: 'read-terminator-failure', operator: 'strictEqual'}],
  })), 'adapters/host-node/client-read-terminator.test.mjs'],
  ['published prefix loses the caller-visible row count', [
    ['    attemptId: context.attemptId, rowsYielded,', '    attemptId: context.attemptId, rowsYielded: 0,'],
  ], publishedPrefixes(['rows'], 'read-121-count', 'strictEqual'), publishedRunAcceptance],
  ['published prefix recommends a transparent resume', [
    ['Look it up before deciding whether to open a new read from the beginning.', 'Resume automatically after the prefix.'],
  ], publishedPrefixes(['rows', 'all'], 'read-121-facts', 'deepStrictEqual'), publishedRunAcceptance],
  ['published prefix explanation can be recovered from a copied error', [
    ['const readExplanations = new WeakMap();',
      'const readExplanations = {values: new Map(),\n' +
      '  set(key, value) {this.values.set(JSON.stringify(key), value);},\n' +
      '  get(key) {return this.values.get(JSON.stringify(key));}};'],
  ], publishedPrefixes(['rows', 'all'], 'read-121-custody', 'strictEqual'), publishedRunAcceptance],
  ['non-object frames become successful rows', [
    ["                  if (row === null || typeof row !== 'object' ||\n                      Array.isArray(row)) fail('InvalidResultFrame');", ''],
  ], shape],
  ['lookup responses retain shared mutable owner records', [
    [lookupCapture + lookupCopy, '            return retainDeliveryExplanation(Object.freeze(answer), {'],
  ], lookupSnapshots],
  ['lookup clone skips preservation and contract revalidation', [
    [lookupCopy, '            answer = structuredClone(answer);\n' +
      '            return retainDeliveryExplanation(freezeInput(answer), {'],
  ], lookupAdmission],
  ['malformed JSON loses its typed refusal', [
    ["                  catch { fail('InvalidResultFrame'); }", '                  catch (cause) { throw cause; }'],
  ], syntax],
  ['invalid rows increase the yielded count', [
    ['                  let row;', '                  rowsYielded++;\n                  let row;'],
    ['                    rowsYielded++;\n                    yield output;', '                    yield output;'],
    ['              for (const row of acceptText(decoder.decode())) {\n' +
      '                const output = await acceptRow(row);\n' +
      '                controller.signal.throwIfAborted();\n' +
      '                rowsYielded++;',
      '              for (const row of acceptText(decoder.decode())) {\n' +
      '                const output = await acceptRow(row);\n' +
      '                controller.signal.throwIfAborted();'],
  ], shape],
  ['absent lookup becomes Host delivery success', [
    ["const observation = answer.kind === 'not_found' ? 'lookup_unresolved'", "const observation = answer.kind === 'not_found' ? 'host_delivery_succeeded'"],
  ], observations('before-commit'), observationAcceptance],
  ['an uncertain opening is described as a confirmed stopped read', [
    ["state === 'opening' ? {observation: 'read_open_unknown'} : undefined", 'undefined'],
  ], observations('after-commit'), observationAcceptance],
  ['confirmed Delivery loses its receipt reference', [
    ['hostReleaseReceiptCid: answer.hostReleaseReceipt.result_delivery_receipt_cid,', ''],
  ], observations('normal'), observationAcceptance],
  ['copied lookup acquires original observation custody', [
    ['const deliveryExplanations = new WeakMap();',
      'const deliveryExplanations = {values: new Map(),\n' +
      '  set(key, value) {this.values.set(JSON.stringify(key), value);},\n' +
      '  get(key) {return this.values.get(JSON.stringify(key));}};'],
  ], observations('after-commit'), observationAcceptance],
];
const accepted = (tests, entry = acceptance) => {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '60', '--', '--test-name-pattern',
    `^(?:${tests.map(value => value.name).join('|')})$`, entry],
  {encoding: 'utf8', timeout: 70000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, tests, entry);
};
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--match' || !args[1])) {
  throw new Error('Usage: check-read-row-mutations.mjs [--match name-substring]');
}
const selected = mutations.filter(([name]) => !args.length || name.includes(args[1]));
if (!selected.length) throw new Error('No read mutations selected');
const originals = new Map(selected.map(([, , , , mutationPath = path]) =>
  [mutationPath, readFileSync(mutationPath, 'utf8')]));
const results = [];
try {
  for (const [name, replacements, tests, entry, mutationPath = path] of selected) {
    const original = originals.get(mutationPath);
    let source = original;
    for (const [from, to] of replacements) {
      if (source.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
      source = source.replace(from, to);
    }
    writeFileSync(mutationPath, source);
    try { results.push({name, rejected: !accepted(tests, entry)}); }
    finally { writeFileSync(mutationPath, original); }
  }
} finally {
  for (const [mutationPath, original] of originals) writeFileSync(mutationPath, original);
}
const restorations = new Map(selected.map(([, , tests, entry]) =>
  [JSON.stringify([entry ?? acceptance, tests]), {tests, entry}]));
const restoredAccepted = [...restorations.values()].every(({tests, entry}) => accepted(tests, entry));
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
