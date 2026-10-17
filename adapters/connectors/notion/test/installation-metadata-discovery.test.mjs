import assert from 'node:assert/strict';
import test from 'node:test';
import {metadataDiscoveryFixture} from './installation-metadata-discovery.fixture.mjs';
import {NOTION_DATABASE_RETRIEVE_OPERATION as databaseOperation,
  NOTION_DATA_SOURCE_RETRIEVE_OPERATION as sourceOperation} from '../site/database-discovery.mjs';

test('actual Notion pre-schema discovery consumes one original Host metadata Subject without a fake Program Run',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async original=>{
    const reader=original.reader(),result=await reader.read();
    assert.equal(result.declaration,original.declaration);
    assert.equal(original.provider.notionReadSourceSelectionMatches(result.selection,result.declaration,result.database),true);
    assert.equal(original.provider.notionDataSourceReadMatches(result.readContracts,result.declaration,result.source),true);
    assert.deepEqual(f.state.requests.map(x=>[x.method,x.path]),[['GET','/v1/databases/db'],['GET','/v1/data_sources/s']]);
    assert.equal(f.state.requests.every(x=>x.originalMaterial&&x.version==='2026-03-11'),true);
    assert.deepEqual(result.responseCharges,f.state.charges);assert.equal(f.state.observations.length,2);
    assert.equal(reader.observe().cleanupConfirmed,false);
    const subject=original.control.subjectFields();assert.equal(Object.keys(subject).length,11);
    assert.equal(subject.declarationSourceCid,original.provider.notionReadDatabaseDeclarationSourceCid(original.declaration));
    assert.equal(Object.hasOwn(subject,'runInvocationCid'),false);assert.equal(Object.hasOwn(subject,'taskAttempt'),false);
    assert.equal(f.journal.recover().filter(x=>x.outcome==='succeeded').length,2);
  });
});

test('actual Notion metadata requires observed lazy selection and rejects a foreign or wrong-purpose original before I/O',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async x=>{
    assert.throws(()=>x.reader({sourceAuthorizationFor:undefined,sourceAuthorization:x.options.initialAuthorization}),
      {code:'NotionMetadataSelectionRequired'});
    const source=x.scopeFor(sourceOperation,'/v1/data_sources/s','early-source');
    assert.throws(()=>x.reader({initialAuthorization:x.authorize(source,'wrong-purpose')}),
      {code:'ForeignNotionDiscoveryAuthorization'});
    const equalSubject=x.view.admitSubject(x.view.subjectWire(x.subject),x.view.subjectCid(x.subject));
    const foreignScope=x.view.prepareScope(equalSubject,x.control.scopeFields(x.options.initialAuthorization.scope));
    assert.throws(()=>x.reader({initialAuthorization:{...x.options.initialAuthorization,scope:foreignScope}}),
      {code:'ForeignInstallationPreparationMetadata'});
    assert.equal(f.state.requests.length,0);assert.equal(f.state.secrets,0);
  });
});

test('actual Notion dependent metadata rejects copied scopes wrong operations and another origin without a schema request',async t=>{
  for(const kind of ['copy','operation','origin']){
    const f=await metadataDiscoveryFixture(t);
    await f.run(async x=>{
      const reader=x.reader({sourceAuthorizationFor:async input=>{
        const original=await x.options.sourceAuthorizationFor(input);
        if(kind==='copy')return{...original,scope:Object.freeze({...original.scope})};
        const fields=x.control.scopeFields(original.scope);
        const scope=x.view.prepareScope(x.subject,{...fields,...(kind==='operation'?{operation:databaseOperation}:
          {resourceOrigin:'https://foreign.example.test'})});
        return x.authorize(scope,'wrong-selected-'+kind);
      }});
      let failure;await assert.rejects(reader.read(),cause=>{failure=cause;
        assert.equal(cause.code,'NotionDatabaseDiscoveryFailed');
        assert.equal(cause.cause.code,kind==='copy'?'ForeignInstallationPreparationMetadata':'ForeignNotionDiscoveryAuthorization');return true;});
      assert.equal(f.state.requests.length,1);assert.equal(f.state.secrets,1);
      assert.equal(failure.observations.length,1);assert.deepEqual(failure.responseCharges,f.state.charges);
      assert.equal(f.state.observations.length,0);assert.equal(reader.observe().cleanupConfirmed,false);
      await assert.rejects(reader.read(),{code:'NotionDiscoveryAlreadyStarted'});assert.equal(f.state.requests.length,1);
    });
  }
});

test('actual Notion physical metadata scope checks the exact selected path and original retained response',async t=>{
  const f=await metadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader({sourceAuthorizationFor:async input=>{
      const original=await x.options.sourceAuthorizationFor(input);
      return x.authorize(x.view.prepareScope(x.subject,{...x.control.scopeFields(original.scope),
        requestPath:'/v1/data_sources/other'}),'wrong-path');
    }});
    let failure;await assert.rejects(reader.read(),cause=>{failure=cause;
      assert.equal(cause.code,'NotionDatabaseDiscoveryFailed');assert.equal(cause.cause.code,'InvalidRemoteCredentialOperation');return true;});
    assert.equal(f.state.requests.length,1);assert.equal(f.state.secrets,1);
    assert.equal(failure.observations.length,1);assert.deepEqual(failure.responseCharges,f.state.charges);
    assert.equal(reader.observe().cleanupConfirmed,false);
  });
});

test('actual Notion original publication and Account remain current through the awaited dependent selection',async t=>{
  for(const kind of ['profile','account','abort']){
    const f=await metadataDiscoveryFixture(t);
    await assert.rejects(f.run(async x=>{
      const stop=new AbortController();
      const reader=x.reader({signal:stop.signal,sourceAuthorizationFor:async input=>{
        const original=await x.options.sourceAuthorizationFor(input);
        if(kind==='profile')await import('node:fs/promises').then(({writeFile})=>writeFile(f.profilePath,'{"version":"changed"}'));
        if(kind==='account')await import('node:fs/promises').then(async({readFile,writeFile})=>{
          const document=JSON.parse(await readFile(f.accountPath,'utf8'));document.entries[0].outcome='deny';
          await writeFile(f.accountPath,JSON.stringify(document));});
        if(kind==='abort')stop.abort();return original;
      }});
      let failure;await assert.rejects(reader.read(),cause=>{failure=cause;return cause.code==='NotionDatabaseDiscoveryFailed';});
      assert.equal(f.state.requests.length,1);assert.equal(f.state.secrets,1);
      assert.equal(failure.observations.length,1);assert.deepEqual(failure.responseCharges,f.state.charges);
      assert.equal(reader.observe().cleanupConfirmed,false);
      if(kind==='profile')assert.equal(failure.cause.code,'InstalledSourcePublicationChanged');
      if(kind==='account')assert.equal(failure.cause.code,'AuthorizationCurrentAccountChanged');
      if(kind==='abort')assert.equal(failure.cause.name,'AbortError');
      // Propagate the actual reader failure through the Host. Swallowing it
      // would cause a second publication-current check after retirement.
      throw failure;
    }),{code:'NotionDatabaseDiscoveryFailed'});
  }
});

test('actual Notion lost dependent metadata reply retains the original journal Unknown without resend',async t=>{
  const f=await metadataDiscoveryFixture(t);
  f.state.reply=(request,response)=>{
    if(request.url==='/v1/data_sources/s'){response.destroy();return;}
    return{object:'database',id:'db',data_sources:[{id:'s',name:'tasks'}]};
  };
  await f.run(async x=>{
    const reader=x.reader();let failure;
    await assert.rejects(reader.read(),cause=>{failure=cause;return cause.code==='NotionDatabaseDiscoveryFailed';});
    assert.equal(f.state.requests.length,2);assert.equal(failure.observations.length,1);
    assert.equal(f.journal.recover().filter(row=>row.outcome==='unknown').length,1);
    assert.equal(reader.observe().cleanupConfirmed,false);
    const resolutions=f.state.secrets;await assert.rejects(reader.read(),{code:'NotionDiscoveryAlreadyStarted'});
    assert.equal(f.state.requests.length,2);assert.equal(f.state.secrets,resolutions);
  });
});
