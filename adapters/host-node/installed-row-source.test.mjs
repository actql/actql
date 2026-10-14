import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {createInstalledRowSource, openRowSourceCredentialSite,
  rowSourceCheckEnvironment} from
  './installed-row-source.mjs';
import {installedSourceReadAccesses, installedSourceReadBindings} from
  './installed-source.mjs';
import {verifyOrdinarySourceBinding} from './ordinary-source-binding.mjs';

test('ordinary row binding is issued by the original preparation owner and rechecks its target', async () => {
  const read = name => readFile(new URL(`../../${name}`, import.meta.url), 'utf8');
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [{resource: 'records',
      resource_kind: 'record', fields: [{name: 'id', type: 'number', nullable: false}]}]}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(
    (await read('spec/local-check-environment.json')).trimEnd(), declared);
  const checkedEnvironment = moon.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
  const preparedProgram = moon.clientProgramPrepareEffectFree(
    JSON.stringify({version: 'actql/0.1', id: 'bound-row-control', stages: [{id: 'scan',
      inputs: {remote: {connector: 'fixture', resource: 'records'}},
      steps: [{filter: 'true', as: 'all_rows'}, {select: ['id'], as: 'output'}],
      results: {r: {from: 'output', fields: ['id']}}}],
      results: {r: {from: {stage: 'scan', result: 'r'}}}}), 'json', checkedEnvironment);
  assert.ok(preparedProgram);
  const [registry, aoa] = await Promise.all([
    read('spec/dependencies/aoa-pipeline-registry.json'), read('spec/contracts/actql-aoa.json').then(JSON.parse)]);
  const expectedBinding = {connectorId: 'fixture', connectorRegistration: 'fixture',
    connectorRevision: 'fixture/0.1', bindingCid: `sha256:${'a'.repeat(64)}`};
  let generation = 1, reads = 0, grants = 0;
  const options = {moon, declaration, declared, environmentWire: environment.wire, ...expectedBinding,
    site: {connection: 'fixture:records', issueReadGrant() {grants++;}, close() {}},
    authorization: {authorize: async () => ({action: 'dispatch'}),
      accountConfiguration: '{}', context: {contextCid: 'context'}}, readOperation: 'read',
    physicalTarget: (resource, fields) => ({resource, fields: [...fields], generation}),
    readPages: async () => {reads++;},
    limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 10, maxCaptureRows: 10}};
  const adapter = await createInstalledRowSource(options);
  const preparation = {preparedProgram, registry,
    values: JSON.stringify(aoa.execution_contracts['REL.values']),
    fragment: JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
    ordered: JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])};
  const prepared = await adapter.prepare(preparation);
  assert.deepEqual(adapter.ordinaryRecoveryBinding(prepared), expectedBinding);
  assert.equal(Object.isFrozen(adapter.ordinaryRecoveryBinding(prepared)), true);
  assert.throws(() => adapter.ordinaryRecoveryBinding({...prepared}),
    {code: 'InstalledSourcePreparationMismatch'});
  const other = await createInstalledRowSource({...options, connectorRevision: 'fixture/other'});
  assert.throws(() => other.ordinaryRecoveryBinding(prepared),
    {code: 'InstalledSourcePreparationMismatch'});
  const freshPrepared = await other.prepare(preparation);
  assert.throws(() => verifyOrdinarySourceBinding(other, freshPrepared, expectedBinding),
    {code: 'InstalledSourcePreparationMismatch'});
  generation = 2;
  assert.throws(() => adapter.ordinaryRecoveryBinding(prepared),
    {code: 'InstalledSourcePreparationMismatch'});
  await assert.rejects(adapter.openCapture({...preparation, preparedSource: prepared, ledger: {}}),
    error => error.cause?.code === 'InstalledSourcePreparationMismatch');
  assert.equal(reads, 0); assert.equal(grants, 0);
});

test('row source exposes exact read tuples for every declared view', async () => {
  const authorization = {authorize: async () => ({action: 'dispatch'}),
    accountConfiguration: '{}', context: {contextCid: 'context'}};
  const views = [{resource: 'issues', resource_kind: 'issue', fields:
    [{name: 'id', type: 'number', nullable: false}]},
  {resource: 'comments', resource_kind: 'comment', fields:
    [{name: 'id', type: 'number', nullable: false}]}];
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(
    declaration));
  const adapter = await createInstalledRowSource({moon, declaration,
    declared, environmentWire: '{}', connectorId: 'fixture',
    connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    site: {connection: 'example:connection', close() {}}, authorization,
    readOperation: 'read', physicalTarget: () => ({}),
    readPages: async () => {}, bindingCid: `sha256:${'a'.repeat(64)}`,
    limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 10,
      maxCaptureRows: 10}});
  assert.equal(adapter.sourceAccess.sourceRef, undefined);
  assert.deepEqual(installedSourceReadAccesses(adapter).map(access => ({
    sourceRef: access.sourceRef, resource: access.resource,
    connection: access.connection,
  })), declared.views.map(view => ({sourceRef: view.source_ref,
    resource: view.resource, connection: 'example:connection'})));
  assert.ok(installedSourceReadAccesses(adapter).every(access =>
    access.authorization === adapter.sourceAccess.authorization &&
    adapter.admitsSource(access.sourceRef)));
  assert.throws(() => adapter.retainedCapture({}),
    {code: 'InstalledSourcePreparationMismatch'});
  assert.deepEqual(installedSourceReadBindings(adapter),
    declared.views.map(view => view.source_ref));
  assert.throws(() => installedSourceReadAccesses({sourceReadAccesses: []}),
    {message: 'InvalidInstalledSourceReadAccesses'});
  assert.throws(() => installedSourceReadBindings({...adapter,
    sourceReadAccesses: [adapter.sourceReadAccesses[0],
      adapter.sourceReadAccesses[0]]}),
  {message: 'InvalidInstalledSourceReadAccesses'});
  assert.throws(() => installedSourceReadBindings({...adapter,
    sourceReadAccesses: [{...adapter.sourceReadAccesses[0],
      sourceRef: 'connector://foreign/r#v'}]}),
  {message: 'InvalidInstalledSourceReadAccesses'});
});

test('plural row operations are closed before any credential grant or page read', async () => {
  const views = ['files', 'contents'].map(resource => ({resource, resource_kind: 'file',
    fields: [{name: 'id', type: 'number', nullable: false}]}));
  const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
    'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views}), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  let grants = 0, reads = 0;
  const options = {moon, declaration, declared, environmentWire: '{}', connectorId: 'fixture',
    connectorRegistration: 'fixture', connectorRevision: 'fixture/0.1',
    site: {connection: 'fixture:files', issueReadGrant() { grants++; }, close() {}},
    authorization: {authorize: async () => ({action: 'dispatch'}),
      accountConfiguration: '{}', context: {contextCid: 'context'}},
    physicalTarget: () => ({}), readPages: async () => { reads++; }, bindingCid: `sha256:${'a'.repeat(64)}`,
    limits: {maxPages: 2, maxPageBytes: 1024, maxPageRows: 10, maxCaptureRows: 10}};
  for (const readOperation of [undefined, '', [], {files: 'list'},
    {files: 'list', contents: ''}, {files: 'list', contents: 'read', extra: 'read'}]) {
    await assert.rejects(createInstalledRowSource({...options, readOperation}),
      {code: 'InvalidInstalledRowSourceOperations'});
  }
  assert.equal(grants, 0); assert.equal(reads, 0);
});

test('checked row capture admits its exact ceiling and refuses one more',
  async () => {
    const read = name => readFile(new URL(`../../${name}`, import.meta.url),
      'utf8');
    const base = (await read('spec/local-check-environment.json')).trimEnd();
    const view = {views: [{resource: 'issues', resource_kind: 'issue', fields:
      [{name: 'id', type: 'number', nullable: false}]}]};
    const declaration = checked(moon.clientProgramRowSourceRestoreDeclaration(
      'fixture', 'fixture', 'fixture/0.1', JSON.stringify(view), undefined));
    const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(
      declaration));
    const environment = rowSourceCheckEnvironment(base, declared);
    const checkedEnvironment = moon.clientProgramCheckEnvironment(
      environment.wire, environment.evidenceCid,
      false, false, true, false, false, false, false);
    assert.ok(checkedEnvironment);
    const document = JSON.stringify({version: 'actql/0.1', id: 'capture-limit',
      stages: [{id: 'acquire',
        inputs: {remote: {connector: 'fixture', resource: 'issues'}},
        steps: [{filter: 'id >= 0', as: 'nonnegative'},
          {select: ['id'], as: 'rows'}],
        results: {r: {from: 'rows', fields: ['id']}}}],
      results: {r: {from: {stage: 'acquire', result: 'r'}}}});
    const prepared = moon.clientProgramPrepareEffectFree(
      document, 'json', checkedEnvironment);
    assert.ok(prepared);
    const [registry, aoa, queryContract, evidenceContract] = await Promise.all([
      read('spec/dependencies/aoa-pipeline-registry.json'),
      read('spec/contracts/actql-aoa.json').then(JSON.parse),
      read('spec/contracts/actql-query-acquisition.json'),
      read('spec/contracts/actql-query-process-evidence.json'),
    ]);
    const required = moon.clientProgramPrepareLocalQueryRequirement(
      prepared, 0, 0, registry,
      JSON.stringify(aoa.execution_contracts['REL.values']),
      JSON.stringify(aoa.execution_contracts[
        'ACTQL.expression_fragment/0.1']),
      JSON.stringify(aoa.execution_contracts['REL.derive.ordered']));
    assert.equal(required.$tag, 1, inspect(required, {depth: 4}));
    const requirement = checked(required);
    const acquired = moon.clientProgramRowSourcePrepareAcquisition(
      declaration, requirement, queryContract, evidenceContract);
    assert.equal(acquired.$tag, 1, inspect(acquired, {depth: 12}));
    const acquisition = checked(acquired);
    assert.equal(checked(moon.clientProgramRowSourceRequestWire(acquisition)),
      '{}');
    const page = Buffer.from('[{"id":1},{"id":2}]', 'utf8');
    const exact = checked(moon.clientProgramRowSourceStart(
      acquisition, 'exact', () => true));
    const binding = 'row-capture/original-run/task-0/input-0';
    let exported;
    try {
      checked(moon.clientProgramRowSourceBegin(exact, 1024, 2, 2));
      assert.equal(checked(moon.clientProgramRowSourceAcceptPage(exact, page)), 2);
      checked(moon.clientProgramRowSourceFinish(exact));
      const captured = checked(moon.clientProgramRowSourceCapture(exact));
      const source = checked(moon.clientProgramRowSourceCaptureSource(captured));
      exported = checked(moon.clientProgramExportSourceCapture(source, requirement, binding));
    } finally { moon.clientProgramRowSourceClose(exact); }
    // A closed physical RowRun is restored through the common Source owner,
    // using its checked acquisition capacity, not a DuckDB-shaped substitute.
    const capacity = moon.clientProgramInstalledRowCaptureCapacity(acquisition);
    assert.ok(capacity);
    const saved = [moon.clientProgramSourceCaptureExportRequirement(exported),
      binding, binding, moon.clientProgramSourceCaptureExportDescriptor(exported),
      moon.clientProgramSourceCaptureExportRows(exported)];
    assert.deepEqual(saved[4], ['{"id":1}', '{"id":2}']);
    assert.throws(() => checked(moon.clientProgramRestoreSourceCapture(requirement,
      ...saved, undefined, capacity, () => false)), {code: 'MoonBitHostFailure'});
    const foreignProgram = moon.clientProgramPrepareEffectFree(
      document.replace('capture-limit', 'foreign-capture'), 'json', checkedEnvironment);
    assert.ok(foreignProgram);
    const foreignRequirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
      foreignProgram, 0, 0, registry,
      JSON.stringify(aoa.execution_contracts['REL.values']),
      JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
      JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
    assert.notEqual(moon.clientProgramQueryRequirementCid(foreignRequirement),
      moon.clientProgramQueryRequirementCid(requirement));
    const foreignAcquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(
      declaration, foreignRequirement, queryContract, evidenceContract));
    assert.throws(() => checked(moon.clientProgramRestoreSourceCapture(requirement,
      ...saved, undefined, moon.clientProgramInstalledRowCaptureCapacity(foreignAcquisition),
      () => true)), {code: 'MoonBitHostFailure'});
    const restored = checked(moon.clientProgramRestoreSourceCapture(requirement,
      ...saved, undefined, capacity, () => true));
    try {
      const source = moon.clientProgramSourceCaptureSource(restored);
      assert.ok(source);
      const again = checked(moon.clientProgramExportSourceCapture(source, requirement, binding));
      assert.deepEqual(moon.clientProgramSourceCaptureExportRows(again), saved[4]);
      assert.equal(moon.clientProgramSourceCaptureExportDescriptor(again), saved[3]);
      assert.ok(moon.clientProgramSourceCaptureUsage(restored).some(value => value > 0n));
    } finally { assert.equal(moon.clientProgramCloseSourceCapture(restored), true); }
    assert.equal(moon.clientProgramSourceCaptureCleanupPending(restored), false);
    assert.deepEqual(moon.clientProgramSourceCaptureUsage(restored), [0n, 0n, 0n]);
    assert.equal(moon.clientProgramSourceCaptureSource(restored), undefined);
    assert.equal(moon.clientProgramCloseSourceCapture(restored), true);
    const oneShort = checked(moon.clientProgramRowSourceStart(
      acquisition, 'one-short', () => true));
    try {
      checked(moon.clientProgramRowSourceBegin(oneShort, 1024, 2, 1));
      const refused = moon.clientProgramRowSourceAcceptPage(oneShort, page);
      assert.equal(refused.$tag, 0, inspect(refused, {depth: 4}));
      assert.match(refused._0?._0?._0?.constructor.name ?? '',
        /CaptureLimit$/u, inspect(refused, {depth: 4}));
      assert.throws(() => checked(moon.clientProgramRowSourceFinish(oneShort)),
        {code: 'MoonBitHostFailure'});
      assert.throws(() => checked(moon.clientProgramRowSourceCapture(oneShort)),
        {code: 'MoonBitHostFailure'});
    } finally { moon.clientProgramRowSourceClose(oneShort); }
  });

test('row acquisition exposes the actual bound Request without normalizing selectors',
  async () => {
    const read = name => readFile(new URL(`../../${name}`, import.meta.url), 'utf8');
    const schemaWire = '{"id":{"nullable":false,"type":"number"}}';
    // The expectation is an authored canonical field map, hashed independently
    // of the product declaration and Request encoder.
    const schemaCid = `sha256:${createHash('sha256').update(schemaWire).digest('hex')}`;
    const requestSchema = {type: 'object', nullable: false,
      additional_properties: false, fields: {
        paths: {type: 'array', nullable: true, max_items: 8,
          items: {type: 'string', nullable: false}},
        glob: {type: 'string', nullable: true},
        prefix: {type: 'string', nullable: false},
      }};
    const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
      'fixture', 'fixture', 'fixture/0.1', JSON.stringify({views: [{
        resource: 'files', resource_kind: 'file', schema_wire: schemaWire,
        schema_cid: schemaCid, request_schema_wire: JSON.stringify(requestSchema),
        facts_wire: '{}',
      }]}), undefined));
    const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
    const environment = rowSourceCheckEnvironment(
      (await read('spec/local-check-environment.json')).trimEnd(), declared);
    const checkedEnvironment = moon.clientProgramCheckEnvironment(
      environment.wire, environment.evidenceCid,
      false, false, true, false, false, false, false);
    assert.ok(checkedEnvironment);
    const [registry, aoa, queryContract, evidenceContract] = await Promise.all([
      read('spec/dependencies/aoa-pipeline-registry.json'),
      read('spec/contracts/actql-aoa.json').then(JSON.parse),
      read('spec/contracts/actql-query-acquisition.json'),
      read('spec/contracts/actql-query-process-evidence.json'),
    ]);
    for (const selector of [
      {paths: ['é.pdf', 'e\u0301.pdf'], glob: null},
      {paths: [], glob: null},
      {paths: null, glob: 'a\\?.pdf'},
    ]) {
      const document = JSON.stringify({version: 'actql/0.1', id: 'request-data',
        params: {prefix: {type: 'string', nullable: false}},
        stages: [{id: 'scan', inputs: {remote: {
          connector: 'fixture', resource: 'files',
          request: {...selector, prefix: {$param: 'prefix'}},
        }}, steps: [{filter: 'id >= 0', as: 'filtered'},
          {select: ['id'], as: 'output'}],
        results: {r: {from: 'output', fields: ['id']}}}],
        results: {r: {from: {stage: 'scan', result: 'r'}}}});
      const preparation = moon.clientProgramPrepareEffectFreeWithParameters(
        document, 'json', checkedEnvironment, JSON.stringify({prefix: 'e\u0301/%2F/'}));
      const prepared = moon.clientProgramPreparationReady(preparation);
      assert.ok(prepared, inspect(moon.clientProgramPreparationIssue(preparation), {depth: 12}));
      const requirement = checked(moon.clientProgramPrepareLocalQueryRequirement(
        prepared, 0, 0, registry, JSON.stringify(aoa.execution_contracts['REL.values']),
        JSON.stringify(aoa.execution_contracts['ACTQL.expression_fragment/0.1']),
        JSON.stringify(aoa.execution_contracts['REL.derive.ordered'])));
      const acquisition = checked(moon.clientProgramRowSourcePrepareAcquisition(
        declaration, requirement, queryContract, evidenceContract));
      assert.deepEqual(JSON.parse(checked(moon.clientProgramRowSourceRequestWire(acquisition))),
        {...selector, prefix: 'e\u0301/%2F/'});
    }
  });

test('the row source Site refuses an undeclared response header before any credential use',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-row-site-'));
    const key = generateKeyPairSync('ed25519');
    await writeFile(join(root, 'credential.key'), key.privateKey.export({
      type: 'pkcs8', format: 'pem'}));
    let resolved = 0;
    const site = await openRowSourceCredentialSite({
      profile: {credentialPrivateKeyPath: join(root, 'credential.key'),
        credentialAuthorityId: 'authority-a', credentialKeyId: 'key-a',
        journalRoot: join(root, 'journal'),
        resourceOrigin: 'https://api.example.test', namespaceId: 'namespace-a',
        environment: 'test', siteKey: 'site-a', siteGeneration: 1},
      principalId: 'principal-a',
      authorization: {issued: () => false, context: {contextCid: 'context'}},
      connection: 'example:connection', connectorRegistration: 'example',
      connectorRevision: 'example/0.1', runtimeBundleCid: `sha256:${'a'.repeat(64)}`,
      commonMoon: moon, resolveSecret: async () => { resolved++; return 'x'; },
      admitsApprovalTarget: () => false, responseHeaders: ['link']});
    // Close the Site before its directory is removed.
    t.after(async () => {
      site.close();
      await rm(root, {recursive: true, force: true});
    });
    assert.throws(() => site.callResource({operations: new Map([['op',
      {method: 'GET', path: '/x', responseHeaders: ['link', 'x-secret']}]])}),
    {code: 'UndeclaredResponseHeader'});
    assert.equal(resolved, 0);
    assert.deepEqual(site.credential.journal.recover(), []);
    await assert.rejects(openRowSourceCredentialSite({profile: {},
      responseHeaders: 'link'}), {code: 'InvalidRowSourceCredentialSite'});
  });

test('invalid declared response headers refuse before opening the credential journal',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-row-site-invalid-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const key = generateKeyPairSync('ed25519');
    await writeFile(join(root, 'credential.key'), key.privateKey.export({
      type: 'pkcs8', format: 'pem'}));
    let opens = 0;
    const options = {
      profile: {credentialPrivateKeyPath: join(root, 'credential.key'),
        credentialAuthorityId: 'authority-a', credentialKeyId: 'key-a',
        journalRoot: join(root, 'journal'),
        resourceOrigin: 'https://api.example.test', namespaceId: 'namespace-a',
        environment: 'test', siteKey: 'site-a', siteGeneration: 1},
      principalId: 'principal-a', connection: 'example:connection',
      connectorRegistration: 'example', connectorRevision: 'example/0.1',
      runtimeBundleCid: `sha256:${'a'.repeat(64)}`, commonMoon: moon,
      authorization: {issued: () => false, context: {contextCid: 'context'}},
      resolveSecret: async () => 'x', admitsApprovalTarget: () => false,
      openCredentialJournal: () => { opens++; return {close() {}}; },
    };
    for (const responseHeaders of ['link', ['link', ''], ['link', 3]]) {
      await assert.rejects(openRowSourceCredentialSite({...options,
        responseHeaders}), {code: 'InvalidRowSourceCredentialSite'});
    }
    assert.equal(opens, 0);
  });
