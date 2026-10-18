import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,writeFile} from 'node:fs/promises';
import test from 'node:test';
import {captureNotionDatabaseDiscoveryPublication as capture,
  notionDatabaseDiscoveryPublicationOriginals as originals} from '../site/database-discovery.mjs';
import {siteMetadataDiscoveryFixture} from './site-metadata-discovery.fixture.mjs';

const limits=Object.freeze({maxBytes:131072,maxNodes:16384,maxDepth:32});
const hash=value=>'sha256:'+createHash('sha256').update(value).digest('hex');

test('live publication capture retains actual Host request Catalog snapshot and both original Site use observations',async t=>{
  const f=await siteMetadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader(),result=await reader.read(),token=await capture(reader,result,limits),view=originals(token);
    assert(Object.isFrozen(token));assert(Object.isFrozen(view));assert.equal(originals(token),view);
    assert.equal(view.publicationRequest,x.options.publication.request);
    assert.deepEqual(view.publicationOriginals,x.options.publication.originals);
    assert.equal(view.subject,x.control.projection(x.options.initialAuthorization.grant).subject);
    assert.equal(view.control,x.control);assert.equal(view.credentialJournal,x.journal);
    for(const name of ['declaration','database','selection','source','readContracts','schemaWire','observations','responseCharges'])assert.equal(view[name],result[name]);
    assert.equal(x.provider.notionDatabaseReadSnapshotMatches(view.snapshot,result.selection,result.source,result.readContracts),true);
    assert.equal(hash(view.snapshotWire),view.snapshotSourceCid);assert.equal(hash(view.declarationWire),view.declarationSourceCid);
    assert.deepEqual(view.operations.map(x=>[x.index,x.operation,x.method,x.path,x.metadataOccurrenceId]),[
      [0,'notion:databases:retrieve','GET','/v1/databases/db','database'],
      [1,'notion:data-sources:retrieve','GET','/v1/data_sources/s','schema']]);
    for(const[index,wire]of[view.databaseWire,view.sourceWire].entries()){
      const observed=view.operations[index];assert(Object.isFrozen(observed));
      assert.equal(observed.response,result.observations[index]);assert.equal(observed.useCid,result.observations[index].useCid);
      assert.equal(observed.bodyCid,hash(wire));assert.equal(observed.bodyBytes,Buffer.byteLength(wire));
      const projection=x.control.projection(observed.grant);assert.equal(projection.subject,view.subject);assert.equal(projection.scope,observed.scope);
      assert.equal(x.control.scopeFields(observed.scope).metadataOccurrenceId,observed.metadataOccurrenceId);
    }
    assert.equal(x.journal.recover().filter(x=>x.outcome==='succeeded').length,2);
    assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(f.state.requests.length,2);
  });
});

test('publication capture refuses copies mixed reader results and another capture without new metadata I/O',async t=>{
  const f=await siteMetadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader(),other=x.reader(),result=await reader.read();
    for(const[r,value]of[[reader,{...result}],[other,result]])await assert.rejects(capture(r,value,limits),{code:'ForeignNotionDiscoveryPublicationResult'});
    const token=await capture(reader,result,limits);
    assert.throws(()=>originals({...token}),{code:'ForeignNotionDiscoveryPublication'});
    await assert.rejects(capture(reader,result,limits),{code:'NotionDiscoveryPublicationAlreadyCaptured'});
    assert.equal(f.state.requests.length,2);assert.equal(reader.observe().cleanupConfirmed,false);
  });
});

test('publication origin is captured before I/O and copied requests or a missing original cannot issue live capture',async t=>{
  const f=await siteMetadataDiscoveryFixture(t);
  await f.run(async x=>{
    assert.throws(()=>x.reader({publication:{...x.options.publication,request:{...x.options.publication.request}}}));
    const reader=x.reader({publication:undefined}),result=await reader.read();
    await assert.rejects(capture(reader,result,limits),{code:'NotionDiscoveryPublicationUnavailable'});
    assert.equal(f.state.requests.length,2);assert.equal(reader.observe().cleanupConfirmed,false);
  });
});

test('live capture rechecks actual publication Account and Site after read and never reopens a failed capture',async t=>{
  for(const kind of ['profile','account','site']){
    const f=await siteMetadataDiscoveryFixture(t);
    await assert.rejects(f.run(async x=>{
      const reader=x.reader(),result=await reader.read();
      const path=kind==='profile'?f.profilePath:kind==='account'?f.accountPath:x.sitePath;
      const document=JSON.parse(await readFile(path,'utf8'));
      if(kind==='profile')document.connectorId='foreign';
      if(kind==='account')document.entries[0].outcome='deny';
      if(kind==='site')document.siteGeneration++;
      await writeFile(path,JSON.stringify(document));
      let failure;await assert.rejects(capture(reader,result,limits),cause=>{failure=cause;return true;});
      assert.equal(f.state.requests.length,2);assert.equal(reader.observe().cleanupConfirmed,false);
      // Propagate the actual failure through the original Host cleanup owner.
      throw failure;
    }));
  }
});

test('capture binds retained Catalog bytes to the response before charge callbacks can mutate the raw alias',async t=>{
  const f=await siteMetadataDiscoveryFixture(t);
  await f.run(async x=>{
    const reader=x.reader({chargeResponse:body=>{
      const ticket=x.options.chargeResponse(body),text=body.toString('utf8');
      if(text.includes('"object":"database"')){
        const modified=Buffer.from(text.replace('tasks','other'));assert.equal(modified.byteLength,body.byteLength);modified.copy(body);
      }
      return ticket;
    }});
    const result=await reader.read();
    await assert.rejects(capture(reader,result,limits),{code:'NotionDiscoveryPublicationObservationMismatch'});
    await assert.rejects(capture(reader,result,limits),{code:'NotionDiscoveryPublicationAlreadyCaptured'});
    assert.equal(result.observations.length,2);assert.deepEqual(result.responseCharges,f.state.charges);
    assert.equal(reader.observe().cleanupConfirmed,false);assert.equal(f.state.requests.length,2);
  });
});
