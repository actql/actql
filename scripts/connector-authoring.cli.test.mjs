import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,rmSync,readdirSync,realpathSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';

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
  const built=JSON.parse(invoke(['build',started.definition,output]));
  assert.equal(built.registration,'acme');assert.equal(built.customMoonBitPackages,0);
  assert.equal(built.runtimeExecuted,false);assert.deepEqual(built.authorFiles,['connector.json']);
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
