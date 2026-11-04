// Actual public read fixtures reuse the existing named-assertion mutation guard.
// Import, timeout and unselected-test failures are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/internal/result-read.mjs';
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
  [
    "const readExplanations = new WeakMap();",
    "const readExplanations = new WeakMap();\nconst unsafeReadRecomputations = new WeakSet();"
  ],
  [
    "const readFailure = (cause, context, rowsYielded, prior) => {",
    "const readFailure = (cause, context, rowsYielded, prior) => {\n  unsafeReadRecomputations.add(context.ref);"
  ],
  [
    "import {captureResponse, freezeInput, positive} from './data.mjs';",
    "import {captureResponse, freezeInput, positive} from './data.mjs';\nimport {unsafeReadSubmissions} from './submission-observation.mjs';"
  ],
  [
    "        try {\n          const response = await runRequest('read', {",
    "        try {\n          if (unsafeReadRecomputations.delete(ref)) {\n            await unsafeReadSubmissions.get(getExecution())?.();\n          }\n          const response = await runRequest('read', {"
  ],
  [
    "const submissionInputs = new WeakMap();",
    "const submissionInputs = new WeakMap();\nexport const unsafeReadSubmissions = new WeakMap();",
    "packages/sdk/internal/submission-observation.mjs"
  ],
  [
    "        submissionInputs.set(run, snapshot);",
    "        submissionInputs.set(run, snapshot);\n        unsafeReadSubmissions.set(run, () => submit(snapshot.kind, snapshot.input,\n          {parameters: snapshot.parameters}));",
    "packages/sdk/internal/submission-observation.mjs"
  ]
], ['local', 'https'].flatMap(entrance => ['rows', 'all'].map(consumer => ({
    name: `${entrance}: ${consumer} remains incomplete after all published rows when the terminator is lost`,
    assertions: [{id: 'read-reread-no-compute', operator: 'deepStrictEqual'}],
  }))), 'adapters/host-node/client-read-terminator.test.mjs'],
  ['a reordered reread skips the previous prefix without a resume contract', [
  [
    "const readExplanations = new WeakMap();",
    "const readExplanations = new WeakMap();\nconst unsafeReadOffsets = new WeakMap();"
  ],
  [
    "const readFailure = (cause, context, rowsYielded, prior) => {",
    "const readFailure = (cause, context, rowsYielded, prior) => {\n  const offsets = unsafeReadOffsets.get(context.ref) ?? new Map();\n  offsets.set(context.resultName, Math.max(offsets.get(context.resultName) ?? 0, rowsYielded));\n  unsafeReadOffsets.set(context.ref, offsets);"
  ],
  [
    "      let rowsYielded = 0, rawRows = 0, retainedBytes = 0;",
    "      const unsafeOffset = unsafeReadOffsets.get(ref)?.get(name) ?? 0;\n      let rowsYielded = 0, rawRows = 0, retainedBytes = 0;"
  ],
  [
    "              const output = await acceptRow(row, size);\n              controller.signal.throwIfAborted();\n              rowsYielded++;\n              yield output;",
    "              const output = await acceptRow(row, size);\n              controller.signal.throwIfAborted();\n              if (rawRows <= unsafeOffset) continue;\n              rowsYielded++;\n              yield output;"
  ],
  [
    "                  rowsYielded++;\n                  yield output;",
    "                  if (rawRows <= unsafeOffset) continue;\n                  rowsYielded++;\n                  yield output;"
  ],
  [
    "              rowsYielded++;\n              yield output;\n            }\n            if (line",
    "              if (rawRows <= unsafeOffset) continue;\n              rowsYielded++;\n              yield output;\n            }\n            if (line"
  ]
], ['local', 'https'].flatMap(entrance => ['rows', 'all'].map(consumer => ({
    name: `${entrance}: explicit reordered ${consumer} reread never skips the previous prefix`,
    assertions: [{id: 'read-reordered-whole-value', operator: 'deepStrictEqual'}],
  }))), 'adapters/host-node/client-read-reorder.test.mjs'],
  ['an uncertain read opening silently creates another charged attempt', [
  [
    "    createDigest: installed.createDigest,\n    authorize,\n    signal,\n  }, Object.isFrozen(index) && Object.isFrozen(manifest)\n    ? Object.freeze({store: installed.store, control: installed.control,\n      index, manifest}) : undefined);\n}",
    "    createDigest: installed.createDigest,\n    authorize,\n    signal,\n  }, Object.isFrozen(index) && Object.isFrozen(manifest)\n    ? Object.freeze({store: installed.store, control: installed.control,\n      index, manifest}) : undefined).catch(cause => {\n    if (input.attemptId.startsWith('unsafe-retry:')) throw cause;\n    return deliverAuthorizedResult(service,\n      {...input, attemptId: 'unsafe-retry:' + globalThis.crypto.randomUUID()}, sink, signal);\n  });\n}"
  ]
], ['local', 'https'].map(entrance => ({
    name: `${entrance}: opening reply lost after-commit is looked up without reopening or consuming another grant`,
    assertions: [{id: 'read-opening-no-retry', operator: 'strictEqual'},
      {id: 'read-opening-no-retry', operator: 'deepStrictEqual'}],
  })), 'adapters/host-node/client-read-opening.test.mjs', 'adapters/host-common/result-access.mjs'],
  ['lost terminator is treated as a completed HTTPS read', [
  [
    "            if (line !== '\\x1e') fail('IncompleteResultStream');",
    ""
  ]
], ['rows', 'all'].map(consumer => ({
    name: `https: ${consumer} remains incomplete after all published rows when the terminator is lost`,
    assertions: [{id: 'read-terminator-failure', operator: 'strictEqual'}],
  })), 'adapters/host-node/client-read-terminator.test.mjs'],
  ['lost terminator returns the buffered all value', [
  [
    "        throw readFailure(cause, readerContexts.get(reader), 0, readExplanations.get(cause));",
    "        return values;"
  ]
], ['local', 'https'].map(entrance => ({
    name: `${entrance}: all remains incomplete after all published rows when the terminator is lost`,
    assertions: [{id: 'read-terminator-failure', operator: 'strictEqual'}],
  })), 'adapters/host-node/client-read-terminator.test.mjs'],
  ['published prefix loses the caller-visible row count', [
  [
    "    attemptId: context.attemptId, rowsYielded,",
    "    attemptId: context.attemptId, rowsYielded: 0,"
  ]
], publishedPrefixes(['rows'], 'read-121-count', 'strictEqual'), publishedRunAcceptance, "packages/sdk/operation-presentation.mjs"],
  ['published prefix recommends a transparent resume', [
  [
    "Look it up before deciding whether to open a new read from the beginning.",
    "Resume automatically after the prefix."
  ]
], publishedPrefixes(['rows', 'all'], 'read-121-facts', 'deepStrictEqual'), publishedRunAcceptance, "packages/sdk/operation-presentation.mjs"],
  ['published prefix explanation can be recovered from a copied error', [
  [
    "const readExplanations = new WeakMap();",
    "const readExplanations = {values: new Map(),\n  set(key, value) {this.values.set(JSON.stringify(key), value);},\n  get(key) {return this.values.get(JSON.stringify(key));}};"
  ]
], publishedPrefixes(['rows', 'all'], 'read-121-custody', 'strictEqual'), publishedRunAcceptance],
  ['non-object frames become successful rows', [
  [
    "                if (row === null || typeof row !== 'object' ||\n                    Array.isArray(row)) fail('InvalidResultFrame');",
    ""
  ]
], shape],
  ['lookup responses retain shared mutable owner records', [
  [
    "          answer = captureResponse(answer);\n          if (!validDeliveryAttemptLookup(answer, expected)) fail('InvalidHostAttemptLookup');\n          return retainDeliveryExplanation(freezeInput(answer), {",
    "          if (!validDeliveryAttemptLookup(answer, expected)) fail('InvalidHostAttemptLookup');\n          return retainDeliveryExplanation(Object.freeze(answer), {"
  ]
], lookupSnapshots],
  ['lookup clone skips preservation and contract revalidation', [
  [
    "          if (!validDeliveryAttemptLookup(answer, expected)) fail('InvalidHostAttemptLookup');",
    ""
  ]
], lookupAdmission],
  ['malformed JSON loses its typed refusal', [
  [
    "                catch { fail('InvalidResultFrame'); }",
    "                catch (cause) { throw cause; }"
  ]
], syntax],
  ['invalid rows increase the yielded count', [
  [
    "                let row;",
    "                rowsYielded++;\n                let row;"
  ],
  [
    "                  rowsYielded++;\n                  yield output;",
    "                  yield output;"
  ],
  [
    "            for (const row of acceptText(decoder.decode())) {\n              const output = await acceptRow(row);\n              controller.signal.throwIfAborted();\n              rowsYielded++;",
    "            for (const row of acceptText(decoder.decode())) {\n              const output = await acceptRow(row);\n              controller.signal.throwIfAborted();"
  ]
], shape],
  ['absent lookup becomes Host delivery success', [
  [
    "const observation = answer.kind === 'not_found' ? 'lookup_unresolved'",
    "const observation = answer.kind === 'not_found' ? 'host_delivery_succeeded'"
  ]
], observations('before-commit'), observationAcceptance, "packages/sdk/operation-presentation.mjs"],
  ['an uncertain opening is described as a confirmed stopped read', [
  [
    "state === 'opening' ? {observation: 'read_open_unknown'} : undefined",
    "undefined"
  ]
], observations('after-commit'), observationAcceptance],
  ['confirmed Delivery loses its receipt reference', [
  [
    "hostReleaseReceiptCid: answer.hostReleaseReceipt.result_delivery_receipt_cid,",
    ""
  ]
], observations('normal'), observationAcceptance, "packages/sdk/operation-presentation.mjs"],
  ['copied lookup acquires original observation custody', [
  [
    "const deliveryExplanations = new WeakMap();",
    "const deliveryExplanations = {values: new Map(),\n  set(key, value) {this.values.set(JSON.stringify(key), value);},\n  get(key) {return this.values.get(JSON.stringify(key));}};"
  ]
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
// Each injected name stays in its actual module/closure. A cross-owner fault
// patches both original modules together; an undefined monolith variable is
// infrastructure failure, never a semantic mutation kill.
const originals = new Map();
for (const [, replacements, , , mutationPath = path] of selected) {
  for (const [from, , target = mutationPath] of replacements) {
    if (!originals.has(target)) originals.set(target, readFileSync(target, 'utf8'));
    if (originals.get(target).split(from).length !== 2) throw new Error('Mutation anchor not unique');
  }
}
const groups = new Map(selected.map(([, , tests, entry]) =>
  [JSON.stringify([entry ?? acceptance, tests]), {tests, entry}]));
const baselines = [...groups.values()].map(({tests, entry}) =>
  ({entry: entry ?? acceptance, names: tests.map(test => test.name), accepted: accepted(tests, entry)}));
if (baselines.some(result => !result.accepted)) throw new Error('Mutation baseline refused');
const results = [];
try {
  for (const [name, replacements, tests, entry, mutationPath = path] of selected) {
    const changed = new Map();
    for (const [from, to, target = mutationPath] of replacements) {
      const source = changed.get(target) ?? originals.get(target);
      if (source.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
      changed.set(target, source.replace(from, to));
    }
    for (const [target, source] of changed) writeFileSync(target, source);
    try { results.push({name, rejected: !accepted(tests, entry)}); }
    finally { for (const target of changed.keys()) writeFileSync(target, originals.get(target)); }
  }
} finally {
  for (const [target, original] of originals) writeFileSync(target, original);
}
const restoredSources = [...originals].every(([target, original]) => readFileSync(target, 'utf8') === original);
const restorations = new Map(selected.map(([, , tests, entry]) =>
  [JSON.stringify([entry ?? acceptance, tests]), {tests, entry}]));
const restoredAccepted = [...restorations.values()].every(({tests, entry}) => accepted(tests, entry));
console.log(JSON.stringify({baselines, mutations: results, restoredSources, restoredAccepted}, null, 2));
if (!restoredSources || !restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
