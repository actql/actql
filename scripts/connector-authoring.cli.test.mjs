import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,rmSync,readdirSync,realpathSync,mkdirSync,symlinkSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {connectorConformancePlan} from './connector.mjs';
import {projectRestConnector} from './connector-authoring.mjs';

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
  const refused=spawnSync(process.execPath,[cli,'build',join(author,'connector.json'),output],{cwd:root,encoding:'utf8'});
  assert.equal(refused.status,1);assert.match(refused.stderr,/RestAuthoringValidatorUnavailable/u);
  assert.deepEqual(readdirSync(scratch),['author']);
  assert.deepEqual(readdirSync(author),['connector.json']);
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
