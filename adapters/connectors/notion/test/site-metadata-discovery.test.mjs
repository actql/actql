import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import test from 'node:test';
import {siteMetadataDiscoveryFixture} from './site-metadata-discovery.fixture.mjs';

test('actual original Site signs and claims separate database and dependent schema uses through Notion discovery',async t=>{
  const f=await siteMetadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader(),result=await reader.read();
    assert.equal(result.declaration,x.declaration);
    assert.equal(x.provider.notionReadSourceSelectionMatches(result.selection,x.declaration,result.database),true);
    assert.equal(x.provider.notionDataSourceReadMatches(result.readContracts,x.declaration,result.source),true);
    assert.deepEqual(f.state.requests.map(x=>[x.method,x.path]),[['GET','/v1/databases/db'],['GET','/v1/data_sources/s']]);
    assert.equal(f.state.requests.every(x=>x.originalMaterial&&x.version==='2026-03-11'),true);
    assert.equal(f.state.secrets,2);assert.deepEqual(result.responseCharges,f.state.charges);
    assert.equal(f.state.observations.length,2);assert.equal(reader.observe().cleanupConfirmed,false);
    assert.equal(x.control.kind,'installation-metadata');
    const subject=x.control.subjectFields();assert.equal(Object.keys(subject).length,11);
    assert.equal(subject.declarationSourceCid,x.provider.notionReadDatabaseDeclarationSourceCid(x.declaration));
    assert.equal(Object.hasOwn(subject,'runInvocationCid'),false);
    const recovered=x.journal.recover();assert.equal(recovered.length,2);
    assert.equal(recovered.every(use=>use.outcome==='succeeded'),true);
  });
});

test('actual metadata Site prevents a changed original publication or Account across dependent selection from sending schema',async t=>{
  for(const kind of ['profile','account','site']){
    const f=await siteMetadataDiscoveryFixture(t);
    await assert.rejects(f.run(async x=>{
      f.state.onSchema=async()=>{
        const path=kind==='profile'?f.profilePath:kind==='account'?f.accountPath:x.sitePath;
        const document=JSON.parse(await readFile(path,'utf8'));
        if(kind==='profile')document.connectorId='foreign';
        if(kind==='account')document.entries[0].outcome='deny';
        if(kind==='site')document.siteGeneration++;
        await writeFile(path,JSON.stringify(document));
      };
      const reader=x.reader();let failure;
      await assert.rejects(reader.read(),cause=>{failure=cause;return cause.code==='NotionDatabaseDiscoveryFailed';});
      assert.equal(f.state.requests.length,1);assert.equal(f.state.secrets,1);
      assert.equal(failure.observations.length,1);assert.deepEqual(failure.responseCharges,f.state.charges);
      assert.equal(reader.observe().cleanupConfirmed,false);
      await assert.rejects(reader.read(),{code:'NotionDiscoveryAlreadyStarted'});
      throw failure;
    }),{code:'NotionDatabaseDiscoveryFailed'});
  }
});

test('actual metadata Site retains lost dependent reply Unknown and refuses same-use resend',async t=>{
  const f=await siteMetadataDiscoveryFixture(t);
  f.state.reply=(request,response)=>{
    if(request.url==='/v1/data_sources/s'){response.destroy();return;}
    return{object:'database',id:'db',data_sources:[{id:'s',name:'tasks'}]};
  };
  await f.run(async x=>{
    const reader=x.reader();let failure;
    await assert.rejects(reader.read(),cause=>{failure=cause;return cause.code==='NotionDatabaseDiscoveryFailed';});
    assert.equal(f.state.requests.length,2);assert.equal(f.state.secrets,2);
    assert.equal(failure.observations.length,1);assert.deepEqual(failure.responseCharges,f.state.charges);
    assert.equal(reader.observe().cleanupConfirmed,false);
    assert.equal(x.journal.recover().some(use=>use.outcome==='unknown'),true);
    await assert.rejects(reader.read(),{code:'NotionDiscoveryAlreadyStarted'});
    assert.equal(f.state.requests.length,2);
  });
});
