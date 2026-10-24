import test from 'node:test';
import assert from 'node:assert/strict';
import {createSubmissionOperations,getSubmissionInput,matchesPublishedSubmissionSnapshot} from '../../packages/sdk/internal/submission-observation.mjs';
import {prepareOrdinarySourceManagedInstallation} from './ordinary-source-managed.mjs';
const epoch={version:'actql-submission-epoch/0.1',authorityScopeCid:'sha256:'+'a'.repeat(64),epochNonce:'b'.repeat(64),notBefore:0,expiresAt:Number.MAX_SAFE_INTEGER,authenticator:'c'.repeat(64)};
test('SDK publishes immutable snapshot before pending return and preserves caller value after Host close',async()=>{
 const host=await prepareOrdinarySourceManagedInstallation({}, {validator(){},intent(){return 'sha256:'+'d'.repeat(64);}},false);
 let body,publication,receipt;
 const sourcePreparation={...host,beforeSourceSnapshot(...args){return receipt=host.beforeSourceSnapshot(...args);},
 bindSourceSnapshot(r,b){body=b;return host.bindSourceSnapshot(r,b);},
 publishSourceSnapshot(r,b,p){publication=p;return host.publishSourceSnapshot(r,b,p);}};
 const operations=createSubmissionOperations({endpoint:'actql:embedded',wire:{mode:'local',owner:'local',durability:'durable',consentRefs:[],runners:[]}},
 {submissionEpoch:epoch,scopeRef:epoch.authorityScopeCid},
 {sourcePreparation,exchange(){throw Error('test transport failure');},wasSubmissionDispatched(){return false;}}, {},{isClosed:()=>false,readerCleanups:new Set()});
 const original={version:'actql/0.1',id:'snapshot-original'};
 const pending=operations.start(original);
 const snapshot=getSubmissionInput(pending);
 assert.ok(snapshot);assert.ok(publication);assert.ok(Object.isFrozen(snapshot));
 assert.equal(matchesPublishedSubmissionSnapshot(publication,body),true);
 assert.equal(matchesPublishedSubmissionSnapshot({},body),false);
 assert.equal(matchesPublishedSubmissionSnapshot(publication,{...body}),false);
 assert.throws(()=>host.publishSourceSnapshot(receipt,body,publication),{code:'ForeignInstalledSourceProducer'});
 const failure=await pending.catch(error=>error);
 assert.equal(getSubmissionInput(failure),snapshot);
 assert.deepEqual(await host.close(),{pending:false});
 assert.equal(getSubmissionInput(pending),snapshot);assert.equal(getSubmissionInput(failure),snapshot);
 assert.deepEqual(snapshot.input,original);assert.notEqual(snapshot.input,original);
 assert.deepEqual(Object.keys(publication),[]);
});

test('publication callback failure preserves original producer cleanup and caller snapshot',async()=>{
 let finished=0,body;const receipt={};const cause=Error('fixed publication failure');
 const sourcePreparation={beforeSourceSnapshot(){return receipt;},bindSourceSnapshot(r,b){assert.equal(r,receipt);body=b;},
 publishSourceSnapshot(r,b,p){assert.equal(r,receipt);assert.equal(b,body);assert(matchesPublishedSubmissionSnapshot(p,b));throw cause;},
 intentCid(){return 'sha256:'+'d'.repeat(64);},finishSourceProducer(r){assert.equal(r,receipt);finished++;}};
 const operations=createSubmissionOperations({endpoint:'actql:embedded',wire:{mode:'local',owner:'local',durability:'durable',consentRefs:[],runners:[]}},
 {submissionEpoch:epoch,scopeRef:epoch.authorityScopeCid},
 {sourcePreparation,exchange(){throw Error('transport failure');},wasSubmissionDispatched(){return false;}}, {},{isClosed:()=>false,readerCleanups:new Set()});
 const pending=operations.start({version:'actql/0.1',id:'still-owned'});
 assert.ok(getSubmissionInput(pending));
 assert.equal(await pending.catch(error=>error),cause);assert.equal(finished,1);
 assert.equal(getSubmissionInput(cause),getSubmissionInput(pending));
 assert.equal(getSubmissionInput(pending).input.id,'still-owned');
});

test('Local adapter uses the packaged private SDK custody predicate, not a checkout-only internal import', async()=>{
 const {readFile}=await import('node:fs/promises');
 const {rewriteLocalNodePackageImports}=await import('../../scripts/local-node-package-imports.mjs');
 const privatePort=await import('../../packages/sdk/internal/private-source-preparation.mjs');
 assert.equal(privatePort.matchesPublishedSubmissionSnapshot,matchesPublishedSubmissionSnapshot);
 const source=await readFile(new URL('./ordinary-source-managed.mjs',import.meta.url),'utf8');
 const packaged=rewriteLocalNodePackageImports(source,'adapters/host-node/ordinary-source-managed.mjs');
 assert.match(packaged,/import \{matchesPublishedSubmissionSnapshot\} from ['"]@actql\/sdk\/_internal\/source-preparation['"]/u);
 assert.throws(()=>rewriteLocalNodePackageImports(source.replace('sdk/internal/private-source-preparation.mjs','sdk/internal/submission-observation.mjs'),'ordinary-source-managed.mjs'),/UnpackagedLocalNodeImport/u);
});
