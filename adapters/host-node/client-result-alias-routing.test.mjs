import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';

function program({aliases=2, distinct=false, empty=false}={}) {
  const stageResults = distinct ? {
    keys:{from:'v',fields:['k']}, values:{from:'v',fields:['v']},
  } : {rows:{from:'v',fields:['k','v']}};
  return {version:'actql/0.1',id:'root-alias-routing',stages:[{id:'main',inputs:{},
    steps:[{as:'v',values:{schema:{k:{type:'number',nullable:false},v:{type:'number',nullable:true}},
      rows:empty?[]:[{k:1,v:2},{k:3,v:null}]}}],results:stageResults}],
    results:distinct?{keys:{from:{stage:'main',result:'keys'}},values:{from:{stage:'main',result:'values'}}}:
      Object.fromEntries(Array.from({length:aliases},(_,i)=>['answer'+i,{from:{stage:'main',result:'rows'}}]))};
}
async function fixture(body) {
  const stateDir=await mkdtemp(join(tmpdir(),'actql-root-alias-'));
  let db=await open({stateDir});
  try {await body(db,async()=>{await db.close();db=await open({stateDir});return db;});}
  finally {await db.close();await rm(stateDir,{recursive:true,force:true});}
}
test('single-task root aliases use the general compiler while singleton stays usable',async()=>{
  await fixture(async db=>{
    for(const aliases of [1,2]) {
      const run=await db.start(program({aliases}));
      assert.equal((await run.wait()).status,'succeeded');
      for(let i=0;i<aliases;i++) assert.deepEqual(await run.result('answer'+i).all(),[{k:1,v:2},{k:3,v:null}]);
    }
  });
});
test('distinct Results from one task retain their own projections including empty rows',async()=>{
  await fixture(async db=>{
    for(const empty of [false,true]) {
      const run=await db.start(program({distinct:true,empty}));
      assert.equal((await run.wait()).status,'succeeded');
      assert.deepEqual(await run.result('keys').all(),empty?[]:[{k:1},{k:3}]);
      assert.deepEqual(await run.result('values').all(),empty?[]:[{v:2},{v:null}]);
    }
  });
});
test('alias Run reopens and original submission lookup returns the same retained Run',async()=>{
  await fixture(async(db,reopen)=>{
    const submissionRef=db.newSubmission({nonce:'root-alias-original'});
    const run=await db.start(program(),{submissionRef,attemptId:'root-alias-first'});
    assert.equal((await run.wait()).status,'succeeded');
    const ref=run.ref;
    db=await reopen();
    const attached=await db.attach(ref);
    assert.equal((await attached.wait()).status,'succeeded');
    assert.deepEqual(await attached.result('answer0').all(),await attached.result('answer1').all());
    const first=await db.lookupSubmission(submissionRef),second=await db.lookupSubmission(submissionRef);
    assert.deepEqual(first,second);
    assert.equal(first.kind,'ready');
    assert.deepEqual(first.admission.ref,ref);
  });
});

test('lost multi-result submit reply is looked up without resubmitting the Run',async()=>{
  const {generateKeyPairSync}=await import('node:crypto');
  const {createServer}=await import('node:https');
  const {execFileSync}=await import('node:child_process');
  const {readFile}=await import('node:fs/promises');
  const {getCACertificates,setDefaultCACertificates}=await import('node:tls');
  const {userInfo}=await import('node:os');
  const {connect}=await import('../../packages/node/index.mjs');
  const {openInstalledRemoteHttpHost}=await import('./embedded-local.mjs');
  const stateDir=await mkdtemp(join(tmpdir(),'actql-alias-lost-reply-'));
  const keys=generateKeyPairSync('ed25519'),principalId=userInfo().username;
  let computes=0,submits=0,loseReply=true,client,host,server;
  try {
    host=await openInstalledRemoteHttpHost({directory:stateDir,
      loopbackHttp:false,authenticate:()=>principalId,authorization:{
        accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',
          account_id:'alias-fixture',entries:[{entry_id:'acceptance',outcome:'allow',
            principal:{all:true},connection:{all:true},resource:{all:true},
            operation:{any_of:['read','write']},exclusions:[]}]}),
        reviewers:[{keyId:'reviewer',reviewerId:'reviewer',principalId,
          publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
        reviewReaders:[principalId],hostKey:{keyId:'host',
          privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
        observe(name){if(name==='computed')computes++;},
      }});
    execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1',
      '-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1',
      '-keyout',join(stateDir,'tls.key'),'-out',join(stateDir,'tls.crt')],{stdio:'ignore'});
    const key=await readFile(join(stateDir,'tls.key')),cert=await readFile(join(stateDir,'tls.crt'));
    setDefaultCACertificates([...getCACertificates('default'),cert.toString()]);
    server=createServer({key,cert},(request,response)=>{
      if(request.url.endsWith('/submit-intent')) {
        submits++;
        if(loseReply) {loseReply=false;response.end=()=>{response.destroy();return response;};}
      }
      return host.handler(request,response);
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    client=await connect({mode:'remote',endpoint:`https://127.0.0.1:${server.address().port}/`,token:'fixture-token',durability:'durable'});
    const submissionRef=client.newSubmission({nonce:'lost-alias-original'});
    await assert.rejects(client.start(program(),{submissionRef,attemptId:'lost-alias-first'}),
      error=>error.code==='SubmissionUnknown');
    const lookup=await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind,'ready');
    const run=await client.attach(lookup.admission.ref);
    assert.equal((await run.wait()).status,'succeeded');
    assert.deepEqual(await run.result('answer0').all(),await run.result('answer1').all());
    assert.deepEqual(await client.lookupSubmission(submissionRef),lookup);
    assert.equal(submits,1,'lookup must not retry physical submission');
    assert.equal(computes,1,'reply loss must not compute the aliased Result twice');
  } finally {
    await client?.close();
    if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
    await host?.close();await rm(stateDir,{recursive:true,force:true});
  }
});
