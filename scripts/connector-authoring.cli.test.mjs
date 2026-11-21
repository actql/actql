import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,rmSync,readdirSync,realpathSync,mkdirSync,symlinkSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {connectorConformancePlan} from './connector.mjs';
import {projectRestConnector, restConnectorPackageMetadata} from './connector-authoring.mjs';
import {assertAuthorRestRows, createAuthorRestProvider, readAuthorRestCase, readRestConformanceInput}
  from './fixtures/external-rest/conformance-input.mjs';
import {readAuthorPackage, selectAuthorPackage} from './fixtures/external-rest/author-package.mjs';

test('declarative read author projection retains closed request DATA and rejects colliding parameters', () => {
  const definition = {version: 'actql-rest-connector/0.1', id: 'acme', origin: 'https://api.example.invalid',
    auth: {kind: 'bearer'}, sources: {records: {fields: [{name: 'id', type: 'string', nullable: false}],
      read: {method: 'GET', path: '/v1/records'}, pagination: {kind: 'cursor', items: ['data'],
        next: ['next_cursor'], parameter: 'after'}, limits: {maxPageRows: 100, maxPageBytes: 4096,
        maxPages: 3, maxRows: 200, maxNodes: 1024, maxDepth: 12, maxCursorBytes: 256}}}};
  const project = () => JSON.parse(projectRestConnector(definition).files['src/connectors/acme/rest-source.json']);
  assert.deepEqual(JSON.parse(project().sources[0].readWire), {method: 'GET', path: '/v1/records'});
  definition.sources.records.read = {method: 'GET', path: '/v1/records', query: [['kind', 'public']],
    pageSize: {parameter: 'page_size', limit: 100}, versionHeader: {name: 'api-version', value: '2026-03-11'}};
  assert.deepEqual(JSON.parse(project().sources[0].readWire), definition.sources.records.read);
  definition.sources.records.read.query.push(['after', 'replacement-cursor']);
  assert.throws(project, /InvalidRestConnectorDefinition:read/u);
});

// Actual author command boundary only. Bare Host imports remain in generated
// module DATA; this test never imports a provider/Host or supplies a grant.
test('the public REST toolkit CLI scaffolds, builds and checks one authored package without a provider compiler', t => {
  const root=fileURLToPath(new URL('../',import.meta.url));
  const scratch=mkdtempSync(join(realpathSync(tmpdir()),'actql-public-rest-cli-'));
  t.after(()=>rmSync(scratch,{recursive:true,force:true}));
  const author=join(scratch,'author'), output=join(scratch,'package');
  const cli=join(root,'scripts/connector.mjs');
  const invoke=args=>execFileSync(process.execPath,[cli,...args],{cwd:root,encoding:'utf8'});
  const started=JSON.parse(invoke(['init',author,'acme']));
  assert.equal(started.definition,join(author,'connector.json'));
  assert.deepEqual(readdirSync(author),['connector.json']);
  const definition={version:'actql-rest-connector/0.1',id:'acme',origin:'https://api.example.invalid',
    auth:{kind:'bearer'},sources:{customers:{
      fields:[{name:'id',type:'string',nullable:false},{name:'name',type:'string',nullable:true}],
      read:{method:'GET',path:'/v1/customers'},
      pagination:{kind:'cursor',items:['data'],next:['next_cursor'],parameter:'after'},
      limits:{maxPageRows:100,maxPageBytes:65536,maxPages:10,maxRows:1000,
        maxNodes:10000,maxDepth:16,maxCursorBytes:1024},
    }}};
  const wire=JSON.stringify(definition,null,2)+'\n';writeFileSync(started.definition,wire);
  // Source/component preparation reuses the ONE existing same-source public
  // library build. This dev alias is not an ordinary installed-package claim,
  // no connector compiler/pack, and its target is never mutated by the case.
  const scope=join(author,'node_modules','@actql');mkdirSync(scope,{recursive:true});
  symlinkSync(join(root,'packages/local-node'),join(scope,'local-node'),'dir');
  const built=JSON.parse(invoke(['build',started.definition,output]));
  assert.equal(built.registration,'acme');assert.equal(built.customMoonBitPackages,0);
  assert.equal(built.runtimeExecuted,true);assert.equal(built.pureCommonValidation,true);
  assert.equal(built.hostRuntimeExecuted,false);assert.deepEqual(built.authorFiles,['connector.json']);
  const views={views:[{resource:'customers',resource_kind:'record',fields:[
    {name:'id',type:'string',nullable:false},{name:'name',type:'string',nullable:true},
  ]}]};
  const generated=JSON.parse(readFileSync(join(output,'src/connectors/acme/rest-source.json')));
  assert.equal(generated.authoredViewsWire,JSON.stringify(views));
  assert.deepEqual(JSON.parse(readFileSync(join(output,'src/connectors/acme/source-views.json'))),views);
  const manifest=JSON.parse(readFileSync(join(output,'src/connectors/acme/host-bundle.json')));
  assert.equal(manifest.installation.source.profileVersion,'actql-installed-acme-rest-source/0.1');
  assert.equal(manifest.installation.effect,undefined);assert.equal(manifest.installation.providerBundle,undefined);
  assert.match(readFileSync(join(output,'index.mjs'),'utf8'),/export const installedConnectors/u);
  assert.deepEqual(JSON.parse(invoke(['test',started.definition,output])),built);
  const stale=readFileSync(join(output,'index.mjs'),'utf8')+'// deliberately stale freshness input\n';
  writeFileSync(join(output,'index.mjs'),stale);
  const refused=spawnSync(process.execPath,[cli,'test',started.definition,output],{cwd:root,encoding:'utf8'});
  assert.equal(refused.status,1);assert.match(refused.stderr,/StaleRestConnectorProjection:index\.mjs/u);
  assert.equal(readFileSync(join(output,'index.mjs'),'utf8'),stale);
  assert.equal(readFileSync(started.definition,'utf8'),wire);
});

test('author build refuses a missing shipped pure validator before writing a package', t => {
  const root=fileURLToPath(new URL('../',import.meta.url));
  const scratch=mkdtempSync(join(realpathSync(tmpdir()),'actql-author-missing-validator-'));
  t.after(()=>rmSync(scratch,{recursive:true,force:true}));
  const author=join(scratch,'author'),output=join(scratch,'package');
  const cli=join(root,'scripts/connector.mjs');
  const initialized=spawnSync(process.execPath,[cli,'init',author,'acme'],{cwd:root,encoding:'utf8'});
  assert.equal(initialized.status,0,initialized.stderr);
  // CI places TMPDIR below its prepared workspace: a fresh directory can
  // legitimately resolve an ancestor installation. Select a test-owned
  // package with a missing shipped entry, rather than assume no ancestor.
  const validator=join(author,'node_modules','@actql','local-node');mkdirSync(validator,{recursive:true});
  writeFileSync(join(validator,'package.json'),JSON.stringify({name:'@actql/local-node',
    type:'module',exports:{'./connector-authoring':'./missing.mjs'}}));
  const refused=spawnSync(process.execPath,[cli,'build',join(author,'connector.json'),output],{cwd:root,encoding:'utf8'});
  assert.equal(refused.status,1);assert.match(refused.stderr,/RestAuthoringValidatorUnavailable/u);
  assert.deepEqual(readdirSync(scratch),['author']);
  assert.deepEqual(readdirSync(author),['connector.json','node_modules']);
});

test('author child resolves its installed consumer validator and preserves original refusal', t => {
  const root=fileURLToPath(new URL('../',import.meta.url));
  const scratch=mkdtempSync(join(realpathSync(tmpdir()),'actql-author-consumer-resolution-'));
  t.after(()=>rmSync(scratch,{recursive:true,force:true}));
  const consumer=join(scratch,'consumer'),author=join(consumer,'author'),output=join(scratch,'package');
  mkdirSync(consumer);writeFileSync(join(consumer,'package.json'),'{"private":true,"type":"module"}\n');
  const cli=join(root,'scripts/connector.mjs');
  const invoke=args=>spawnSync(process.execPath,[cli,...args],{cwd:root,encoding:'utf8',timeout:10000});
  const initialized=invoke(['init',author,'acme']);assert.equal(initialized.status,0,initialized.stderr);
  const definition=join(author,'connector.json'),original=readFileSync(definition);
  // An explicitly absent public export must refuse even if TMPDIR inherits
  // a matching installation. This is distinct from the missing method below.
  const validator=join(consumer,'node_modules','@actql','local-node');mkdirSync(validator,{recursive:true});
  writeFileSync(join(validator,'package.json'),JSON.stringify({name:'@actql/local-node',
    type:'module',exports:{}}));
  const missing=invoke(['build',definition,output]);
  assert.equal(missing.status,1);assert.equal(missing.signal,null);
  assert.match(missing.stderr,/RestAuthoringValidatorUnavailable: install a matching/u);
  assert.deepEqual(readdirSync(scratch),['consumer']);
  // Explicit test-owned public export controls only. They do not implement or
  // qualify Common validation, a normal package, Host or successful build.
  writeFileSync(join(validator,'package.json'),JSON.stringify({name:'@actql/local-node',
    version:'0.0.0-development',type:'module',exports:{'./connector-authoring':'./author.mjs'}}));
  writeFileSync(join(validator,'author.mjs'),'export const unrelated = true;\n');
  const absentMethod=invoke(['build',definition,output]);
  assert.equal(absentMethod.status,1);assert.equal(absentMethod.signal,null);
  assert.equal(absentMethod.stderr.trim(),'RestAuthoringValidatorUnavailable');
  writeFileSync(join(validator,'author.mjs'),
    'export function validateRestReadDeclaration(wire,cursor) {\n'+
    'const read=JSON.parse(wire);\n'+
    'if(read.method!=="GET"||read.path!=="/v1/records"||cursor!=="after") throw Error("FixtureOriginalReadMismatch");\n'+
    'throw Object.assign(new Error("FixtureParentValidatorReached"),{code:"RestAuthoringValidatorUnavailable"});\n}\n');
  const originalRefusal=invoke(['build',definition,output]);
  assert.equal(originalRefusal.status,1);assert.equal(originalRefusal.signal,null);
  assert.equal(originalRefusal.stderr.trim(),'FixtureParentValidatorReached');
  assert.deepEqual(readFileSync(definition),original);
  assert.deepEqual(readdirSync(author),['connector.json']);
  assert.deepEqual(readdirSync(scratch),['consumer']);
});

test('author projections and freshness use the selected Host package version', t => {
  const root=fileURLToPath(new URL('../',import.meta.url));
  const scratch=mkdtempSync(join(realpathSync(tmpdir()),'actql-author-host-version-'));
  t.after(()=>rmSync(scratch,{recursive:true,force:true}));
  const author=join(scratch,'author'),output=join(scratch,'output');
  const cli=join(root,'scripts/connector.mjs');
  const invoke=(...args)=>spawnSync(process.execPath,[cli,...args],{cwd:scratch,encoding:'utf8',timeout:10000});
  const init=invoke('init',author,'acme');
  assert.equal(init.status,0,init.stderr);
  const definition=join(author,'connector.json');
  const host=join(author,'node_modules','@actql','local-node');
  mkdirSync(host,{recursive:true});
  const manifest=version=>writeFileSync(join(host,'package.json'),JSON.stringify({name:'@actql/local-node',
    version,type:'module',exports:{'./connector-authoring':'./author.mjs'}}));
  // A test-owned public validation port isolates peer selection. It does not
  // stand in for the existing compiled Common validation controls.
  writeFileSync(join(host,'author.mjs'),'export function validateRestReadDeclaration(wire) {return wire;}\n');
  manifest('0.2.1-rc.3');
  const build=invoke('build',definition,output);
  assert.equal(build.status,0,build.stderr);
  const generated=join(output,'package.json');
  const original=readFileSync(generated,'utf8');
  assert.deepEqual(JSON.parse(original).peerDependencies,{'@actql/local-node':'0.2.1-rc.3'});
  const fresh=invoke('test',definition,output);
  assert.equal(fresh.status,0,fresh.stderr);
  manifest('0.2.2');
  const stale=invoke('test',definition,output);
  assert.equal(stale.status,1);
  assert.match(stale.stderr,/StaleRestConnectorProjection:package\.json/u);
  assert.equal(readFileSync(generated,'utf8'),original);
  manifest('*');
  const refused=invoke('build',definition,output);
  assert.equal(refused.status,1);
  assert.match(refused.stderr,/RestAuthoringValidatorUnavailable: invalid selected Host manifest/u);
  assert.equal(readFileSync(generated,'utf8'),original);
});

test('author conformance selects the installed reference case without creating an installation', t => {
  const root=fileURLToPath(new URL('../',import.meta.url));
  const scratch=mkdtempSync(join(realpathSync(tmpdir()),'actql-rest-author-normal-plan-'));
  t.after(()=>rmSync(scratch,{recursive:true,force:true}));
  const input=join(scratch,'normal-input.json');
  const descriptor={kind:'actql-standard-rest-normal/0.1',sourceSha:'a'.repeat(40),
    sourceTree:'b'.repeat(40),manifestPath:join(scratch,'normal-manifest.json'),
    manifestSha256:'c'.repeat(64),outputRoot:join(scratch,'fresh-output'),
    accountConfigurationPath:join(scratch,'account.json'),mode:'paged'};
  writeFileSync(input,JSON.stringify(descriptor));
  const plan=connectorConformancePlan(root,[input,'--timeout-seconds','180']);
  assert.equal(plan.root,root.replace(/\/$/u,''));
  assert.equal(plan.timeoutSeconds,180);assert.equal(plan.heavy,true);
  assert.equal(plan.steps.length,1);
  const [step]=plan.steps;
  assert.equal(step.command,process.execPath);
  assert.equal(step.args.at(-1),'scripts/fixtures/external-rest/normal-case.test.mjs');
  assert.deepEqual(step.env,{ACTQL_REST_CONFORMANCE_INPUT:input});
  // Planning reads only the explicit descriptor. Missing artifacts and Account
  // remain missing; actual source/SRI/lifecycle validation belongs to the case.
  assert.deepEqual(readdirSync(scratch),['normal-input.json']);
  writeFileSync(input,JSON.stringify({...descriptor,mode:'notion-users'}));
  assert.deepEqual(connectorConformancePlan(root,[input,'--timeout-seconds','180']),plan);
  assert.equal(readRestConformanceInput(input).mode,'notion-users');
});

test('author conformance refuses implicit runtime, source-only selection and invalid input', t => {
  const root=fileURLToPath(new URL('../',import.meta.url));
  const scratch=mkdtempSync(join(realpathSync(tmpdir()),'actql-rest-author-normal-refusal-'));
  t.after(()=>rmSync(scratch,{recursive:true,force:true}));
  const input=join(scratch,'normal-input.json');
  const descriptor={kind:'actql-standard-rest-normal/0.1',sourceSha:'a'.repeat(40),
    sourceTree:'b'.repeat(40),manifestPath:join(scratch,'manifest.json'),
    manifestSha256:'c'.repeat(64),outputRoot:join(scratch,'output'),
    accountConfigurationPath:join(scratch,'account.json'),mode:'empty'};
  writeFileSync(input,JSON.stringify(descriptor));
  for(const args of [[],[input],[input,'--timeout-seconds','0'],
    [input,'--test','180'],[input,'--timeout-seconds','180','--stage','source']]) {
    assert.throws(()=>connectorConformancePlan(root,args));
  }
  for(const changed of [{kind:'source'}, {mode:'live'}, {manifestSha256:'missing'},
    {sourceSha:'main'}, {accountConfigurationPath:'account.json'}, {runtime:'implicit'}]) {
    writeFileSync(input,JSON.stringify({...descriptor,...changed}));
    assert.throws(()=>connectorConformancePlan(root,[input,'--timeout-seconds','180']),/descriptor/u);
  }
  const refused=spawnSync(process.execPath,[join(root,'scripts/connector.mjs'),
    'conformance',input,'--timeout-seconds','180'],{cwd:root,encoding:'utf8'});
  assert.equal(refused.status,1);assert.match(refused.stderr,/descriptor/u);
  assert.equal(refused.stdout,'');
  assert.deepEqual(readdirSync(scratch),['normal-input.json']);
});


test('author conformance selects independent connector, schema, Program, bindings and fixture state', t => {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const scratch = mkdtempSync(join(realpathSync(tmpdir()), 'actql-rest-author-case-'));
  t.after(() => rmSync(scratch, {recursive: true, force: true}));
  const fixture = new URL('./fixtures/external-rest/harbor/', import.meta.url);
  const bytes = readFileSync(new URL('case.json', fixture));
  const casePath = join(scratch, 'case.json');
  const connectorPath = join(scratch, 'connector.json');
  writeFileSync(casePath, bytes);
  writeFileSync(connectorPath, readFileSync(new URL('connector.json', fixture)));
  const hash = value => createHash('sha256').update(value).digest('hex');
  const caseSha256 = hash(bytes);
  const input = join(scratch, 'normal-input.json');
  writeFileSync(input, JSON.stringify({kind: 'actql-standard-rest-normal/0.1', mode: 'author',
    sourceSha: 'a'.repeat(40), sourceTree: 'b'.repeat(40), manifestSha256: 'c'.repeat(64),
    manifestPath: join(scratch, 'manifest.json'), outputRoot: join(scratch, 'uncreated'),
    accountConfigurationPath: join(scratch, 'account.json'), casePath, caseSha256}));
  assert.equal(connectorConformancePlan(root, [input, '--timeout-seconds', '180'])
    .steps[0].env.ACTQL_REST_CONFORMANCE_INPUT, input);
  const author = readAuthorRestCase(casePath, caseSha256);
  const {definition} = selectAuthorPackage(casePath, author);
  assert.equal(definition.id, 'harbor');
  assert.deepEqual(Object.keys(definition.sources), ['berths']);
  assert.deepEqual(author.parameters, {minimum_depth: 9});
  const provider = createAuthorRestProvider(author);
  const before = provider.assertState('before');
  const response = provider.handle({method: 'GET', target: '/v2/berths'});
  assert.deepEqual(JSON.parse(response.body).berths.map(row => row.slip_code), ['C-4', 'A-1', 'B-7']);
  provider.assertRequests([{method:'GET',path:'/v2/berths',authorized:true}]);
  assert.deepEqual(provider.assertState('after'), before);
  assertAuthorRestRows(author.expected,[{slip_code:'B-7',depth:9},{slip_code:'C-4',depth:17}]);
  assert.throws(() => assertAuthorRestRows(author.expected, JSON.parse(response.body).berths),
    /independent row oracle/u);
  const wrongSchema = structuredClone(author);
  wrongSchema.schema.fields[1].type = 'string';
  assert.throws(() => selectAuthorPackage(casePath, wrongSchema), /independent case schema/u);
  const wrongControl = structuredClone(author);
  wrongControl.expected.control.harbor_master_note = 'Open Pier D';
  assert.throws(() => createAuthorRestProvider(wrongControl).assertState('after'), /control records differ/u);
  assert.throws(() => readAuthorRestCase(casePath, '0'.repeat(64)), /digest mismatch/u);
  writeFileSync(connectorPath, '{}');
  assert.throws(() => selectAuthorPackage(casePath, author), /digest mismatch/u);
  assert(!readdirSync(scratch).includes('uncreated'));
});


test('author conformance refuses packed install hooks and unexpected dependencies before npm', async t => {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'actql-rest-author-package-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const schema = {registration: 'harbor', resource: 'berths', fields: [{name: 'slip_code', type: 'string', nullable: false}]};
  const hostVersion = '0.0.0-development';
  const original = restConnectorPackageMetadata(schema.registration, hostVersion);
  for (const extra of [{scripts: {install: 'node author-install.mjs'}},
    {dependencies: {'third-party': '1.0.0'}},
    {peerDependencies: {'@actql/local-node': '0.1.0'}}]) {
    writeFileSync(join(root, 'package.json'), JSON.stringify({...original, ...extra}));
    await assert.rejects(readAuthorPackage(root, schema, 'https://127.0.0.1:16120', hostVersion),
      /manifest must match the generated package/u);
  }
  assert.deepEqual(readdirSync(root), ['package.json']);
});
