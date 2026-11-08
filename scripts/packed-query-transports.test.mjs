import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {test} from 'node:test';
import {createTransportOwner, requireCompleteInventory, sourceFixturePaths, observePackedSubmissionCause}
  from './fixtures/packed-query-transport-owner.mjs';
import {encodeRetainedFixture} from './fixtures/retained-fixture-values.mjs';
import {publicQueryResultOracles} from './fixtures/public-query-input.mjs';

const helper = new URL('./fixtures/packed-query-transport-owner.mjs', import.meta.url).href;
const command = (name, source) => ({name, args: ['--input-type=module', '-e', source]});

test('public query HTTPS observation selects only its original operator and authored Result names', async () => {
  const {parse} = await import('acorn');
  const source = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const declarations = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === 'createPublicQueryHttpAuthorization') declarations.push(node);
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(syntax);
  assert.equal(declarations.length, 1);
  const declaration = declarations[0];
  const create = Function('userInfo', 'canonical', 'publicQueryResultOracles',
    `return (${source.slice(declaration.start, declaration.end)});`)(
      () => ({username: 'query-operator'}), JSON.stringify, publicQueryResultOracles);
  const account = JSON.parse(create({primaryResultName: 'selected', successes: [
    {name: 'one'}, {name: 'two', results: {secondary: {}, selected: {}}},
  ]}).accountConfiguration);
  assert.deepEqual(account, {version: 'actql-execution-account-config/0.1',
    account_id: 'packed-query-http', entries: [
      {entry_id: 'read-original', outcome: 'allow', principal: {any_of: ['query-operator']},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: ['result/secondary', 'result/selected', 'run']},
        operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'request-original', outcome: 'allow', principal: {any_of: ['query-operator']},
        connection: {any_of: ['actql-remote-host']}, resource: {any_of: ['duckdb-acquired']},
        operation: {any_of: ['write']}, exclusions: []},
    ]});
  assert.match(source, /authorization: httpAuthorization/u);
  assert.match(source, /recordCohort\('remote', directory, cohort, authorization \?\? httpAuthorization\)/u);
  assert.match(source, /if \(authorization !== undefined\) saved\.authorization = authorization/u);
});

test('public query fixture names preserve explicit and structured exports independently of product output', () => {
  const expected = [{value: 1}], columns = [{name: 'value'}];
  const implicit = {format: 'sql', text: 'SELECT 1 AS value', expected, columns};
  assert.deepEqual(publicQueryResultOracles(implicit), {main: {rows: expected, columns}});
  assert.deepEqual(publicQueryResultOracles({...implicit, resultName: 'answer'}),
    {answer: {rows: expected, columns}});
  for (const format of ['json', 'aql-json']) {
    const structured = {...implicit, format, text: JSON.stringify({results: {answer: {from: {stage: 'main', result: 'answer'}}}})};
    assert.deepEqual(publicQueryResultOracles(structured), {answer: {rows: expected, columns}});
    assert.throws(() => publicQueryResultOracles({...structured,
      text: JSON.stringify({results: {answer: {}, other: {}}})}), /requires authored result oracles/u);
  }
  const results = {original: {rows: expected, columns}, answer: {rows: [], columns}};
  assert.equal(publicQueryResultOracles({...implicit, results}), results);
  assert.equal(publicQueryResultOracles(implicit).main.rows, expected);
});

test('scoped ORDER fixtures read the explicit authored export', async () => {
  const scope = JSON.parse(await readFile(new URL(
    '../spec/frontend/fixtures/pipe-scope/cases.json', import.meta.url), 'utf8'));
  const cases = scope.successes.filter(item => item.name.startsWith('scoped-order-'));
  assert.equal(cases.length, 4);
  for (const item of cases) {
    assert.match(item.text, /\|> RESULT answer$/u);
    assert.equal(item.resultName, 'answer');
    assert.deepEqual(publicQueryResultOracles(item), {
      answer: {rows: item.expected, columns: item.columns},
    });
  }
});
async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-transport-owner-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  return directory;
}

async function diagnosticTarget(t) {
  const directory = await fixture(t), path = join(directory, 'original-ingress.mjs');
  await writeFile(path, `const publicFailure = error => error;
function unusedResult(original) {
  try {throw original;}
  catch (error) {
    throw publicFailure(error);
  }
}
export function originalIngress(original) {
  try {throw original;}
  catch (error) {
    throw publicFailure(error);
  }
}
`);
  const sourceURL = pathToFileURL(path);
  return {path, sourceURL, ...await import(sourceURL.href)};
}

test('packed cause observer captures bounded original DATA and always resumes the same throw', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const original = Object.assign(new TypeError('private-message-never-reported'), {
    code: 'ClientProgramUnsupported', requestId: 'private-request-never-reported',
    cause: Object.assign(new Error('private-inner-never-reported'), {code:'ForeignRequestOriginal'}),
  });
  let reads = 0, enumerations = 0;
  Object.defineProperty(original, '_0', {get() {reads++; throw new Error('accessor invoked');}});
  Object.defineProperty(original, 'unrelatedPrivateField', {get() {reads++; throw new Error('private field read');}});
  const reflected = [];
  const primary = new Proxy(original, {
    ownKeys() {enumerations++; throw new Error('private fields enumerated');},
    getOwnPropertyDescriptor(target, key) {
      reflected.push(key);
      assert.ok(['code','cause','primaryFailure','_0','_1','_2'].includes(key));
      return Reflect.getOwnPropertyDescriptor(target, key);
    },
  });
  original.cause.primaryFailure = primary;
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {
    assert.throws(() => target.originalIngress(primary), error => error === primary);
    assert.throws(() => target.originalIngress(primary), error => error === primary);
  } finally {await observer.close();}
  await observer.close();
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, true);
  assert.equal(reports[0].originalCauseTypes.length, 1, 'only the first original boundary is observed');
  assert.deepEqual(reports[0].originalCauseTypes[0], [
    {edge:'original',type:'TypeError',code:'ClientProgramUnsupported'},
    {edge:'cause',type:'Error',code:'ForeignRequestOriginal'},
    {edge:'_0',type:'Accessor'},
  ]);
  assert.equal(reads, 0);
  assert.equal(enumerations, 0);
  assert.ok(reflected.length > 0);
  assert.ok(!reflected.includes('stack') && !reflected.includes('unrelatedPrivateField'));
  assert.doesNotMatch(JSON.stringify(reports), /private-|requestId|message|stack/u);
});

test('packed cause observer report failure cannot replace the original exception or cleanup', async t => {
  const target = await diagnosticTarget(t);
  const primary = new RangeError('original'), diagnostic = new Error('report unavailable');
  let reports = 0, caught;
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report() {reports++;throw diagnostic;}});
  try {target.originalIngress(primary);}
  catch (error) {caught=error;}
  finally {await observer.close();}
  assert.equal(caught, primary);
  assert.equal(reports, 1);
  assert.throws(() => target.originalIngress(primary), error => error === primary);
});

test('packed cause observer refuses a loaded Source mismatch without changing the original result', async t => {
  const target = await diagnosticTarget(t), reports = [];
  await writeFile(target.path, (await readFile(target.path, 'utf8'))+'\n// changed after original import\n');
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  const primary = new Error('unchanged original');
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
});

test('packed cause observer inspection failure resumes and preserves the original exception', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const primary = new Proxy(new Error('original'), {
    getOwnPropertyDescriptor() {throw new Error('descriptor inspection unavailable');},
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
});

test('packed cause observer never sends a private inspection exception to Inspector formatting', async t => {
  const target = await diagnosticTarget(t), reports = [];
  let reads = 0;
  const privateFailure = new Error('private-inspection-failure');
  for (const name of ['stack', 'message', 'name']) Object.defineProperty(privateFailure, name,
    {get() {reads++;throw new Error('private-inspection-getter');}});
  const primary = new Proxy(new Error('original'), {
    getOwnPropertyDescriptor() {throw privateFailure;},
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reads, 0, 'Reflection failure must stay inside the bounded inspection expression');
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
  assert.deepEqual(reports[0].originalCauseTypes, []);
  assert.doesNotMatch(JSON.stringify(reports), /private-|message|stack/u);
});

test('packed cause observer discards partial DATA when nested reflection fails', async t => {
  const target = await diagnosticTarget(t), reports = [];
  let reads = 0;
  const privateFailure = new Error('private-nested-inspection-failure');
  Object.defineProperty(privateFailure, 'stack', {get() {reads++;throw new Error('private-getter');}});
  const primary = Object.assign(new Error('original'), {code:'ClientProgramUnsupported',
    cause:new Proxy({}, {getOwnPropertyDescriptor() {throw privateFailure;}})});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reads, 0);
  assert.equal(reports[0].available, false);
  assert.deepEqual(reports[0].originalCauseTypes, [], 'The earlier original row is not a complete observation');
  assert.doesNotMatch(JSON.stringify(reports), /private-|ClientProgramUnsupported|message|stack/u);
});

test('packed cause observer retains a closed Node failure code without collecting its message', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const primary = Object.assign(new Error('private-SQL-never-reported'), {code:'ERR_SQLITE_ERROR'});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'Error',code:'ERR_SQLITE_ERROR'}]]);
  assert.doesNotMatch(JSON.stringify(reports), /private-SQL/u);
});

test('packed cause observer omits a plausible private code and forged MoonBit constructor name', async t => {
  const target = await diagnosticTarget(t), reports = [];
  class _MPrivateInputSecret extends Error {}
  const primary = Object.assign(new _MPrivateInputSecret('private-message'), {code:'ClientPrivateInputSecret'});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'MoonBit',codeOmitted:true,codeType:'String'}]]);
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-message/u);
});

test('packed cause observer retains exact factory codes and primitive edge types without their values', async t => {
  const target = await diagnosticTarget(t), reports = [];
  const primary = Object.assign(new Error('private-factory-message'), {
    code:'MoonBitHostFailure', cause:9234567, _0:undefined, _1:null,
    _2:{code:'NodeManagedRunAdmissionUnavailable', cause:'private-primitive-string', primaryFailure:()=> 'private-function',
      _0:true, _1:9234568n, _2:Symbol('private-symbol')},
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(primary), error => error === primary);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[
    {edge:'original',type:'Error',code:'MoonBitHostFailure'},
    {edge:'cause',type:'Number'}, {edge:'_0',type:'Undefined'}, {edge:'_1',type:'Null'},
    {edge:'_2',type:'Object',code:'NodeManagedRunAdmissionUnavailable'}, {edge:'cause',type:'String'},
    {edge:'primaryFailure',type:'Function'}, {edge:'_0',type:'Boolean'},
    {edge:'_1',type:'BigInt'}, {edge:'_2',type:'Symbol'},
  ]]);
  assert.doesNotMatch(JSON.stringify(reports), /9234567|9234568|private-/u);
});

test('packed cause observer retains reviewed Local preparation factory codes with an undefined cause', async t => {
  const codes = ['RunHostCompilationRejected', 'RunHostTaskCompilationRejected',
    'RunHostAdmissionRejected', 'RunHostStaticPlanRejected', 'RunHostOriginalPlanRejected'];
  const factory = await readFile(new URL('../adapters/host-common/runtime-core.mjs', import.meta.url), 'utf8');
  assert(factory.includes("new Error(code, {cause: error.cause})"));
  for (const code of codes) assert(factory.includes(`'${code}'`), code);
  const target = await diagnosticTarget(t), reports = [];
  const error = code => Object.assign(new Error('private-factory-message'), {code, cause:undefined});
  const original = error(codes[0]);
  original.primaryFailure = error(codes[1]); original._0 = error(codes[2]);
  original._1 = error(codes[3]); original._2 = error(codes[4]);
  original._2.cause = error('RunHostPrivateInputSecret');
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(original), value => value === original);}
  finally {await observer.close();}
  assert.equal(reports[0].available, true);
  const rows = reports[0].originalCauseTypes.flat();
  assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]).sort(), [...codes].sort());
  assert.equal(rows.filter(row => row.type === 'Undefined').length, 5);
  assert(rows.some(row => row.type === 'Error' && row.codeOmitted === true));
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-factory-message|message|stack/u);
});

test('packed cause observer retains closed compiled-Run submission factory codes', async t => {
  const codes = [
    'RunHostResultPolicyRejected', 'RunHostResultSelectionRejected',
    'RunHostTaskDefinitionRejected', 'RunHostSourceFreeDefinitionRejected',
    'RunHostSourceFreeAdmissionRejected', 'RunHostTaskInvocationRejected', 'RunHostInvocationRejected',
  ];
  const factory = await readFile(new URL('../adapters/host-common/runtime-core.mjs', import.meta.url), 'utf8');
  assert(factory.includes('new Error(code, {cause: error.cause})'));
  for (const code of codes) assert(factory.includes(`'${code}'`), code);
  const target = await diagnosticTarget(t), reports = [];
  const errors = codes.map(code => Object.assign(new Error('private-submit-boundary'),
    {code, cause:undefined}));
  for (let index = 1; index < errors.length; index++) errors[index - 1].primaryFailure = errors[index];
  let reads = 0;
  Object.defineProperty(errors.at(-1), '_0', {get() {reads++;throw new Error('private-getter');}});
  errors.at(-1)._1 = {code:'RunHostPrivateInputSecret'};
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(errors[0]), error => error === errors[0]);}
  finally {await observer.close();}
  assert.equal(reads, 0);
  assert.equal(reports[0].available, true);
  const rows = reports[0].originalCauseTypes.flat();
  assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]), codes);
  assert.equal(rows.filter(row => row.type === 'Undefined').length, codes.length);
  assert(rows.some(row => row.type === 'Accessor'));
  assert(rows.some(row => row.codeOmitted === true && row.codeType === 'String'));
  assert.doesNotMatch(JSON.stringify(reports), /PrivateInputSecret|private-|message|stack/u);
});

test('packed cause observer classifies omitted code descriptors without getters or values', async t => {
  const target = await diagnosticTarget(t), reports = [];
  let reads = 0;
  const original = Object.assign(new Error('private-code-description'), {
    code:undefined, _0:{code:'PrivateCodeSecret'}, _1:{code:9234567}, _2:{code:{}},
    cause:Object.defineProperty({}, 'code', {get() {reads++;throw new Error('private-getter');}}),
  });
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    report:value=>reports.push(value)});
  try {assert.throws(() => target.originalIngress(original), value => value === original);}
  finally {await observer.close();}
  assert.equal(reads, 0);
  assert.equal(reports[0].available, true);
  assert.deepEqual(reports[0].originalCauseTypes, [[
    {edge:'original',type:'Error',codeOmitted:true,codeType:'Undefined'},
    {edge:'cause',type:'Object',codeOmitted:true,codeType:'Accessor'},
    {edge:'_0',type:'Object',codeOmitted:true,codeType:'String'},
    {edge:'_1',type:'Object',codeOmitted:true,codeType:'Number'},
    {edge:'_2',type:'Object',codeOmitted:true,codeType:'Other'},
  ]]);
  assert.doesNotMatch(JSON.stringify(reports), /PrivateCodeSecret|9234567|private-|message|stack/u);
});

test('packed cause observer covers fixed submit factories without deriving categories from runtime data', {timeout: 30_000}, async t => {
  const {parse} = await import('acorn');
  const modules = [
    'adapters/host-node/in-process-client.mjs', 'adapters/host-node/client-http.mjs',
    'adapters/host-node/client-request-journal.mjs', 'adapters/host-node/client-submission.mjs',
    'adapters/host-node/client-program-preparation.mjs', 'adapters/host-node/client-submit.mjs',
    'adapters/host-node/ordinary-source-managed.mjs', 'adapters/host-node/source-managed-original-input.mjs',
    'adapters/host-node/embedded-local.mjs', 'adapters/host-node/local-account-config.mjs',
    'adapters/host-node/ordinary-local-account.mjs', 'adapters/host-node/ordinary-mock-account.mjs',
    'adapters/host-node/ordinary-host-control.mjs', 'adapters/host-node/ordinary-host-journal.mjs',
    'adapters/host-node/node-host-journal-installation.mjs', 'adapters/host-node/node-source-managed-installation.mjs',
    'adapters/host-node/client-source-operation.mjs', 'adapters/host-node/installed-row-source.mjs',
    'adapters/host-node/bounded-continuation-metadata.mjs', 'adapters/host-node/bounded-continuation-directory.mjs',
    'adapters/host-common/runtime-core.mjs', 'adapters/host-common/runtime-result.mjs',
    'adapters/host-common/sqlite-format-inspection.mjs', 'adapters/host-common/sqlite-transaction.mjs',
  ];
  const syntax = source => parse(source, {ecmaVersion:'latest', sourceType:'module'});
  const helperSource = await readFile(new URL('./fixtures/packed-query-transport-owner.mjs', import.meta.url), 'utf8');
  const declaration = syntax(helperSource).body.flatMap(node => node.declarations ?? [])
    .find(node => node.id.name === 'originalFailureCodes');
  assert.equal(declaration.init.callee.object.name, 'Object');
  assert.equal(declaration.init.callee.property.name, 'freeze');
  const entries = declaration.init.arguments[0];
  assert.equal(entries.type, 'ArrayExpression');
  assert(entries.elements.every(node => node.type === 'Literal' && typeof node.value === 'string'));
  const codes = entries.elements.map(node => node.value), fixed = new Set(codes);
  assert.equal(codes.length, fixed.size);
  const selected = new Set(), factoryArguments = {fail:0, invalid:0,
    clientOperationError:0, compiledRunResult:1, rejectSubmission:0, failure:0};
  const literal = node => {
    if (node?.type === 'Literal' && typeof node.value === 'string' && /^[A-Z][A-Za-z0-9_]+$/u.test(node.value)) {
      selected.add(node.value);
    } else if (node?.type === 'ConditionalExpression') {
      literal(node.consequent); literal(node.alternate);
    } else if (node?.type === 'LogicalExpression') {
      literal(node.left); literal(node.right);
    }
  };
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'CallExpression' && Object.hasOwn(factoryArguments, node.callee.name)) {
      literal(node.arguments[factoryArguments[node.callee.name]]);
    }
    if (node.type === 'AssignmentExpression' && node.left.type === 'MemberExpression' && node.left.property.name === 'code') {
      literal(node.right);
    }
    if (node.type === 'Property' && ['code', 'unavailableCode', 'cleanupCode'].includes(node.key.name ?? node.key.value)) {
      literal(node.value);
    }
    if (node.type === 'VariableDeclarator' && ['issueCodes', 'effectIssueCodes'].includes(node.id.name)) {
      assert.equal(node.init.callee.object.name, 'Object');
      assert.equal(node.init.callee.property.name, 'freeze');
      assert.equal(node.init.arguments[0].type, 'ObjectExpression');
      for (const entry of node.init.arguments[0].properties) literal(entry.value);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  for (const path of modules) visit(syntax(await readFile(new URL('../' + path, import.meta.url), 'utf8')));
  // This actual transaction factory has exactly two selected Journal callers.
  // Expand only their Source-pinned prefixes, never an arbitrary runtime prefix.
  const transaction = await readFile(new URL('../adapters/host-common/sqlite-transaction.mjs', import.meta.url), 'utf8');
  const journal = await readFile(new URL('../adapters/host-node/client-request-journal.mjs', import.meta.url), 'utf8');
  for (const prefix of ['ClientRequestJournal', 'ClientObservation']) {
    assert(journal.includes(`'${prefix}'`));
    for (const suffix of ['ConnectionUnusable', 'CommitOutcomeUnknown', 'RollbackFailed']) {
      assert(transaction.includes('${prefix}' + suffix));
      selected.add(prefix + suffix);
    }
  }
  const http = await readFile(new URL('../adapters/host-node/client-http.mjs', import.meta.url), 'utf8');
  assert(http.includes("responseCode(error) === 500 ? 'ClientHostFailure'"));
  selected.add('ClientHostFailure');
  for (const code of selected) assert(fixed.has(code), 'Missing fixed production factory code: ' + code);
  // Execute all fixed categories in bounded batches. Foreign strings and
  // accessors stay omitted; the live observer still uses only this literal set.
  for (let offset = 0; offset < codes.length; offset += 7) {
    const batch = codes.slice(offset, offset + 7), target = await diagnosticTarget(t), reports = [];
    const originals = batch.map(code => Object.assign(new Error('private-original-message'), {code, cause:undefined}));
    for (let index = 1; index < originals.length; index++) originals[index - 1].primaryFailure = originals[index];
    let reads = 0;
    Object.defineProperty(originals.at(-1), '_0', {get() {reads++;throw new Error('private-getter');}});
    originals.at(-1)._1 = {code:'ClientPrivateFactoryPayload'};
    const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL, report:value=>reports.push(value)});
    try {assert.throws(() => target.originalIngress(originals[0]), error => error === originals[0]);}
    finally {await observer.close();}
    assert.equal(reads, 0); assert.equal(reports[0].available, true);
    const rows = reports[0].originalCauseTypes.flat();
    assert.deepEqual(rows.flatMap(row => row.code === undefined ? [] : [row.code]), batch);
    assert(rows.some(row => row.type === 'Accessor'));
    assert(rows.some(row => row.codeOmitted === true && row.codeType === 'String'));
    assert.doesNotMatch(JSON.stringify(reports), /private-|PrivateFactoryPayload|message|stack/u);
  }
});

async function statusDiagnosticTarget(t, transport, {foreignCaller = false} = {}) {
  const caller = foreignCaller ? 'foreignFailure' : 'publicFailure';
  const directory = await fixture(t), path = join(directory, 'status-ingress.mjs');
  const shared = `const statuses = new WeakMap(); let reads = 0;
const responseCode = error => { reads++; return statuses.get(error); };
export const statusReads = () => reads;
`;
  const source = transport === 'http' ? shared + `
function sendError(response, error) {
  const status = responseCode(error);
  response.writeHead(status, {'content-type': 'application/json'});
}
export function originalIngress(original, status) {
  statuses.set(original, status);
  try {throw original;}
  catch (error) {sendError({writeHead() {}}, error); throw error;}
}
` : shared + `
class ClientError extends Error {
  constructor(code, {status}) {super(code); this.code = code; this.status = status;}
}
const localErrors = new WeakSet();
const publicClientErrorStatus = responseCode;
const publicClientErrorCode = error => statuses.get(error) === 500 ? 'ClientHostFailure' : 'ClientProgramUnsupported';
const publicError = (code, status) => {
  const error = new ClientError(code, {status});
  delete error.stack;
  return error;
};
const ${caller} = error => localErrors.has(error) ? error
  : publicError(publicClientErrorCode(error), publicClientErrorStatus(error));
const host = {perform(operation, original, status) {
  statuses.set(original, status);
  try {throw original;}
  catch (error) {throw ${caller}(error);}
}};
export function originalIngress(original, status, operation = 'submit-intent') {
  return host.perform(operation, original, status);
}
`;
  await writeFile(path, source);
  const sourceURL = pathToFileURL(path);
  return {sourceURL, ...await import(sourceURL.href)};
}

for (const transport of ['http', 'local']) {
  test(`packed cause observer captures only the first ${transport} 500 from its computed status and original frame`, async t => {
    const target = await statusDiagnosticTarget(t, transport), reports = [];
    const expected = Object.assign(new Error('private-decline'), {code:'ClientProgramUnsupported'});
    const original = Object.assign(new Error('private-primary'), {code:'MoonBitHostFailure'});
    let reflected = 0;
    const later = new Proxy(new Error('private-later'), {
      getPrototypeOf() {reflected++; throw new Error('Later original must not be inspected');},
    });
    const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
      boundary:transport + '-500', report:value=>reports.push(value)});
    const unchanged = (error, primary, status) => transport === 'http' ? error === primary
      : error !== primary && error.code === (status === 500 ? 'ClientHostFailure' : 'ClientProgramUnsupported') && error.status === status;
    try {
      assert.throws(() => target.originalIngress(expected, 422), error => unchanged(error, expected, 422));
      assert.throws(() => target.originalIngress(original, 500), error => unchanged(error, original, 500));
      assert.throws(() => target.originalIngress(later, 500), error => unchanged(error, later, 500));
    } finally {await observer.close();}
    assert.equal(target.statusReads(), 3, 'the breakpoint condition must not repeat status classification');
    assert.equal(reflected, 0, 'later errors are not reflected after the first 500');
    assert.equal(reports.length, 1);
    assert.equal(reports[0].available, true);
    assert.deepEqual(reports[0].originalCauseTypes, [[{edge:'original',type:'Error',code:'MoonBitHostFailure'}]]);
    assert.doesNotMatch(JSON.stringify(reports), /private-|decline|later|message|stack/u);
  });
}

test('packed cause observer refuses a different Local caller and still resumes its public outcome', async t => {
  const target = await statusDiagnosticTarget(t, 'local', {foreignCaller:true}), reports = [];
  const original = Object.assign(new Error('private-foreign-caller'), {code:'MoonBitHostFailure'});
  const observer = await observePackedSubmissionCause({sourceURL:target.sourceURL,
    boundary:'local-500', report:value=>reports.push(value)});
  try {
    assert.throws(() => target.originalIngress(original, 500), error =>
      error !== original && error.code === 'ClientHostFailure' && error.status === 500);
  } finally {await observer.close();}
  assert.equal(target.statusReads(), 1);
  assert.equal(reports.length, 1);
  assert.equal(reports[0].available, false);
  assert.equal(reports[0].unavailableReason, 'original-caller-unavailable');
  assert.deepEqual(reports[0].originalCauseTypes, []);
  assert.doesNotMatch(JSON.stringify(reports), /private-|foreignFailure|message|stack/u);
});

test('packed submission cause ignores earlier non-submission failures without inspecting their errors', async t => {
  for (const operation of ['submit', 'submit-intent', 'submit-named-intent', 'restart-intent']) {
    const target = await statusDiagnosticTarget(t, 'local'), reports = [];
    let reflected = 0;
    const unrelated = new Proxy(new Error('private-unrelated'), {
      getPrototypeOf() {reflected++; throw new Error('Unrelated error must not be inspected');},
    });
    const original = Object.assign(new Error('private-submission'), {code: 'RunHostOriginalPlanRejected'});
    const observer = await observePackedSubmissionCause({sourceURL: target.sourceURL,
      boundary: 'local-submission-500', report: value => reports.push(value)});
    try {
      assert.throws(() => target.originalIngress(unrelated, 422, operation),
        {code: 'ClientProgramUnsupported', status: 422});
      for (const prior of ['read', 'result-describe', 'private-operation']) {
        assert.throws(() => target.originalIngress(unrelated, 500, prior),
          {code: 'ClientHostFailure', status: 500});
      }
      assert.throws(() => target.originalIngress(original, 500, operation),
        {code: 'ClientHostFailure', status: 500});
      assert.throws(() => target.originalIngress(unrelated, 500, operation),
        {code: 'ClientHostFailure', status: 500});
    } finally {await observer.close();}
    assert.equal(target.statusReads(), 6, 'Observation never repeats status classification');
    assert.equal(reflected, 0, 'Unrelated and later errors remain uninspected');
    assert.equal(reports.length, 1);
    assert.equal(reports[0].available, true);
    assert.deepEqual(reports[0].originalCauseTypes,
      [[{edge: 'original', type: 'Error', code: 'RunHostOriginalPlanRejected'}]]);
    assert.doesNotMatch(JSON.stringify(reports), /private-|message|stack/u);
  }
});

test('complete transport inventory rejects missing, duplicate, extra and reordered identities', () => {
  // Independently authored expected identities, not generated from a partition.
  const expected = ['standard/success/a', 'standard/failure/b', 'standard/refusal/c'];
  requireCompleteInventory(expected, [...expected]);
  for (const supplied of [expected.slice(0, 2), [...expected, expected[0]],
    [...expected, 'standard/success/foreign'], [...expected].reverse()]) {
    assert.throws(() => requireCompleteInventory(expected, supplied));
  }
  assert.throws(() => requireCompleteInventory(['duplicate', 'duplicate'], ['duplicate', 'duplicate']));
});

test('two actual workers isolate mutable source state and counters and both settle', async t => {
  const directory = await fixture(t);
  assert.deepEqual(sourceFixturePaths('local', 'standard', directory), {
    database: join(directory, 'records.duckdb'), sourceProfilePath: join(directory, 'source-profile.json'),
  });
  assert.deepEqual(sourceFixturePaths('remote', 'standard', directory), {
    database: join(directory, 'records-remote.duckdb'), sourceProfilePath: join(directory, 'source-profile-remote.json'),
  });
  const owner = createTransportOwner({deadline: Date.now() + 5000, forward() {}});
  try {
    await owner.run([['local', 11], ['remote', 17]].map(([mode, expected]) => command(mode, `
      import assert from 'node:assert/strict';
      import {writeFile, readFile} from 'node:fs/promises';
      import {ownTransportWorker, sourceFixturePaths} from ${JSON.stringify(helper)};
      const worker = ownTransportWorker();
      const file = sourceFixturePaths(${JSON.stringify(mode)}, 'standard', ${JSON.stringify(directory)}).database;
      globalThis.sourceCounter = 0;
      try {
        for (let row = 0; row < ${expected}; row++) {
          worker.check();
          await writeFile(file, String(row));
          await new Promise(resolve => setTimeout(resolve, 1));
          assert.equal(await readFile(file, 'utf8'), String(row));
          globalThis.sourceCounter++;
        }
        await writeFile(file + '.count', String(globalThis.sourceCounter));
      } finally { worker.release(); }
    `)));
    assert.equal(await readFile(join(directory, 'records.duckdb.count'), 'utf8'), '11');
    assert.equal(await readFile(join(directory, 'records-remote.duckdb.count'), 'utf8'), '17');
    const report = owner.report();
    assert.equal(report.liveChildren, 0);
    assert.equal(new Set(report.children.map(child => child.pid)).size, 2);
    assert.ok(report.children.every(child => child.terminal && child.status === 0));
  } finally { owner.close(); }
});

test('a worker failure remains primary and sibling cancellation finishes cleanup before release', async t => {
  const directory = await fixture(t);
  const owner = createTransportOwner({deadline: Date.now() + 5000, forward() {}});
  const ready = join(directory, 'ready'), cleaned = join(directory, 'cleaned');
  try {
    await assert.rejects(owner.run([
      command('original-failure', `
        import {access} from 'node:fs/promises';
        for (;;) { try { await access(${JSON.stringify(ready)}); break; }
          catch { await new Promise(resolve => setTimeout(resolve, 1)); } }
        process.exitCode = 9;
      `),
      command('sibling', `
        import {writeFile} from 'node:fs/promises';
        import {ownTransportWorker} from ${JSON.stringify(helper)};
        const worker = ownTransportWorker();
        try {
          await writeFile(${JSON.stringify(ready)}, 'ready');
          for (;;) { worker.check(); await new Promise(resolve => setTimeout(resolve, 1)); }
        } finally { await writeFile(${JSON.stringify(cleaned)}, 'closed'); worker.release(); }
      `),
    ]), /PackedQueryWorkerFailed:original-failure/u);
    assert.equal(await readFile(cleaned, 'utf8'), 'closed');
    assert.equal(owner.report().liveChildren, 0);
    assert.ok(owner.report().children.every(child => child.terminal));
    assert.equal(owner.report().children[0].status, 9);
  } finally { owner.close(); }
});

test('one absolute deadline stops both owned workers without granting a new child budget', async () => {
  const deadline = Date.now() + 200;
  const owner = createTransportOwner({deadline, forward() {}});
  try {
    await assert.rejects(owner.run(['local', 'remote'].map(mode => command(mode, `
      import {ownTransportWorker} from ${JSON.stringify(helper)};
      ownTransportWorker();
      setInterval(() => {}, 1000);
    `))), /PackedQueryAcceptanceDeadline/u);
    assert.equal(owner.report().deadline, deadline);
    assert.equal(owner.report().liveChildren, 0);
    assert.ok(owner.report().children.every(child => child.terminal && child.signal === 'SIGKILL'));
    assert.throws(() => owner.check(), /PackedQueryAcceptanceDeadline/u);
  } finally { owner.close(); }
});

test('the two workers consume one aggregate output allowance', async () => {
  const owner = createTransportOwner({deadline: Date.now() + 5000, outputLimit: 100, forward() {}});
  try {
    await assert.rejects(owner.run(['local', 'remote'].map(mode => command(mode,
      `process.stdout.write('x'.repeat(60));`))), /PackedQueryAggregateOutputLimit/u);
    assert.equal(owner.report().liveChildren, 0);
    assert.equal(owner.report().outputLimit, 100);
  } finally { owner.close(); }
});

test('abrupt coordinator death stops its worker through the owned IPC connection', async t => {
  const directory = await fixture(t);
  const stopped = join(directory, 'stopped');
  const worker = `
    import {writeFileSync} from 'node:fs';
    import {ownTransportWorker} from ${JSON.stringify(helper)};
    ownTransportWorker();
    process.on('exit', () => writeFileSync(${JSON.stringify(stopped)}, 'physically stopped'));
    process.send({ready: true});
    setInterval(() => {}, 1000);
  `;
  const parent = spawn(process.execPath, ['--input-type=module', '-e', `
    import {spawn} from 'node:child_process';
    const child = spawn(process.execPath, ['--input-type=module', '-e', ${JSON.stringify(worker)}],
      {stdio: ['ignore', 'ignore', 'ignore', 'ipc'], detached: false});
    child.once('message', () => process.send({ready: true}));
    process.on('disconnect', () => { child.kill('SIGKILL'); process.exit(1); });
  `], {stdio: ['ignore', 'ignore', 'ignore', 'ipc'], detached: false});
  t.after(() => { if (parent.exitCode === null && parent.signalCode === null) parent.kill('SIGKILL'); });
  const terminal = new Promise(resolve => parent.once('close', resolve));
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('fixture worker did not become ready')), 3000);
    parent.once('message', () => { clearTimeout(timer); resolve(); });
    parent.once('error', error => { clearTimeout(timer); reject(error); });
  });
  parent.kill('SIGKILL');
  await terminal;
  const deadline = Date.now() + 3000;
  for (;;) {
    try { assert.equal(await readFile(stopped, 'utf8'), 'physically stopped'); break; }
    catch (error) {
      if (error.code !== 'ENOENT' || Date.now() >= deadline) throw error;
      await new Promise(resolve => setTimeout(resolve, 5));
    }
  }
});

test('the serial tail runs once after both terminal workers and its failure is retained', async t => {
  const directory = await fixture(t);
  for (const name of ['packed-query-transports.mjs', 'packed-query-transport-owner.mjs',
    'packed-query-worker.mjs', 'retained-fixture-values.mjs',
    'graph-argument-check.mjs', 'graph-argument-origin-literals.json']) {
    await writeFile(join(directory, name), await readFile(new URL(`./fixtures/${name}`, import.meta.url)));
  }
  await writeFile(join(directory, 'acceptance.mjs'), `
    import {writeFile, readFile} from 'node:fs/promises';
    import {encodeRetainedFixture} from './retained-fixture-values.mjs';
    const mode = process.env.ACTQL_TEST_QUERY_TRANSPORT;
    if (mode === 'tail') {
      await readFile('finished.local'); await readFile('finished.remote');
      await writeFile('tail-once', 'one', {flag: 'wx'});
      throw new Error('IndependentlyAuthoredTailFailure');
    }
    const inventory = [JSON.stringify(['standard', 'refusals', 0, 'authored-case', 'a'.repeat(64)])];
    await writeFile('transport-completion.' + mode + '.json', JSON.stringify({mode, complete: true,
      expectedInventory: inventory, completedInventory: inventory, expectedRetainedCohorts: 0, needsTail: true}));
    await writeFile('retained-cohort-results.' + mode + '.json', encodeRetainedFixture([]));
    await writeFile('finished.' + mode, 'finished');
  `);
  const child = spawn(process.execPath, [join(directory, 'packed-query-transports.mjs')], {
    cwd: directory, env: {...process.env, ACTQL_TEST_QUERY_DEADLINE: String(Date.now() + 5000)},
    stdio: ['ignore', 'pipe', 'pipe'], detached: false,
  });
  child.stdout.resume(); child.stderr.resume();
  const timeout = setTimeout(() => child.kill('SIGKILL'), 5000);
  let status;
  try { status = await new Promise(resolve => child.once('close', resolve)); }
  finally { clearTimeout(timeout); }
  assert.equal(status, 1);
  const report = JSON.parse(await readFile(join(directory, 'transport-processes.json'), 'utf8'));
  assert.equal(report.complete, false);
  assert.equal(report.primaryError, 'IndependentlyAuthoredTailFailure');
  assert.equal(report.liveChildren, 0);
  assert.equal(report.children.length, 2);
  assert.ok(report.children.every(receipt => receipt.terminal && receipt.status === 0));
  assert.equal(await readFile(join(directory, 'tail-once'), 'utf8'), 'one');
});

for (const cohortOnly of [false, true]) {
test(`restart assigns each related root to one of two serial transport workers (cohort only: ${cohortOnly})`, async t => {
  const directory = await fixture(t);
  for (const name of ['packed-query-restart-transports.mjs', 'packed-query-transport-owner.mjs',
    'packed-query-worker.mjs', 'retained-fixture-values.mjs']) {
    await writeFile(join(directory, name), await readFile(new URL(`./fixtures/${name}`, import.meta.url)));
  }
  const cohorts = [
    {mode: 'local', directory: 'local-first'}, {mode: 'local', directory: 'local-next'},
    {mode: 'remote', directory: 'remote-first'}, {mode: 'remote', directory: 'remote-next'},
  ];
  await writeFile(join(directory, 'retained-cohort-results.json'), encodeRetainedFixture(cohorts));
  await writeFile(join(directory, 'string-values-restart.mjs'), `
    import {writeFile} from 'node:fs/promises';
    import {transportWorker} from './packed-query-transport-owner.mjs';
    const worker = transportWorker(), mode = process.env.ACTQL_TEST_QUERY_TRANSPORT;
    const expected = mode === 'local' ? ['local-first', 'local-next'] : ['remote-first', 'remote-next'];
    const completedRoots = [];
    for (const root of expected) {
      worker.check();
      await new Promise(resolve => setTimeout(resolve, 1));
      completedRoots.push(root);
    }
    await writeFile('transport-restart.' + mode + '.json', JSON.stringify({mode,
      stringComplete: process.env.ACTQL_TEST_RETAINED_COHORT_ONLY !== '1', completedRoots}));
  `);
  const child = spawn(process.execPath, [join(directory, 'packed-query-restart-transports.mjs')], {
    cwd: directory, env: {...process.env, ACTQL_TEST_RETAINED_COHORT_ONLY: cohortOnly ? '1' : '0',
      ACTQL_TEST_QUERY_RESTART_DEADLINE: String(Date.now() + 5000)},
    stdio: ['ignore', 'pipe', 'pipe'], detached: false,
  });
  child.stdout.resume(); child.stderr.resume();
  const timeout = setTimeout(() => child.kill('SIGKILL'), 5000);
  let status;
  try { status = await new Promise(resolve => child.once('close', resolve)); }
  finally { clearTimeout(timeout); }
  assert.equal(status, 0);
  const report = JSON.parse(await readFile(join(directory, 'transport-restart-processes.json'), 'utf8'));
  assert.equal(report.timeoutMs, 120_000);
  assert.equal(report.complete, true);
  assert.equal(report.liveChildren, 0);
  assert.equal(report.children.length, 2, 'no new process or allowance per root');
  assert.deepEqual(report.roots, [
    {mode: 'local', expectedRoots: 2, completedRoots: 2},
    {mode: 'remote', expectedRoots: 2, completedRoots: 2},
  ]);
});
}
