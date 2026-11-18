import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

// Actual source-checkout Common/Host/Resource/SQLite/Store and SDK/Undici.
// The server is a deterministic HTTP provider, not a real OpenAI acceptance.
async function normalHttpFixture({coldSaved = false, httpStatus = 200, transport = 'response', cancelEntered = false,
  tls = false} = {}) {
  const responseLost = transport === 'response-lost';
  const unknown = responseLost || cancelEntered;
  const count = httpStatus === 200 && !unknown ? 2 : 1;
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-normal-openai-http-',
    label: 'Actual normal Model Host HTTP boundary', preserve: unknown});
  const tasks = {
    'model-task:first': {task: 'model-task:first', instructions: 'Return the exact boolean.',
      input: {text: 'string'}, output: {answer: 'boolean'}, limits: {max_items: 2, max_output_tokens: 100}},
    'model-task:second': {task: 'model-task:second', instructions: 'Return the exact label.',
      input: {quantity: 'number'}, output: {label: 'string'}, limits: {max_items: 2, max_output_tokens: 100}},
  };
  await writeFile(join(scratch.path, 'actql.config.json'),
    JSON.stringify({version: 'actql-config/0.1', model_tasks: './model-tasks.json'}));
  await writeFile(join(scratch.path, 'model-tasks.json'), JSON.stringify({version: 'actql-model-tasks/0.1',
    tasks: {'model-task:first': './first.json', 'model-task:second': './second.json'},
    providers: {'models/http': {type: 'openai'}}, default_provider: 'models/http'}));
  for (const [name, task] of Object.entries(tasks)) {
    await writeFile(join(scratch.path, name.endsWith('first') ? 'first.json' : 'second.json'), JSON.stringify(task));
  }
  await writeFile(join(scratch.path, 'api-key.fixture'), 'not-an-external-secret', {mode: 0o600});
  if (tls) execFileSync('openssl', ['req','-x509','-nodes','-newkey','rsa:2048',
    '-keyout','provider.key','-out','provider.crt','-days','1','-subj','/CN=localhost',
    '-addext','subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd:scratch.path,stdio:'ignore'});
  const host = new URL('./embedded-local.mjs', import.meta.url).href;
  const factory = new URL('../../packages/provider-ai-sdk/index.mjs', import.meta.url).href;
  const fdObserver = new URL('../../scripts/fixtures/external-rest/conformance.mjs', import.meta.url).href;
  const script = `
    import assert from 'node:assert/strict';
    import {createServer} from 'node:http';
    import {createServer as createTlsServer} from 'node:https';
    import {getCACertificates,setDefaultCACertificates} from 'node:tls';
    import {generateKeyPairSync} from 'node:crypto';
    import {writeFile,readFile,access} from 'node:fs/promises';
    import {resolve} from 'node:path';
    import {observeOwnScopedStateFds} from ${JSON.stringify(fdObserver)};
    import {userInfo} from 'node:os';
    import {inspect} from 'node:util';
    import {connectEmbeddedLocal} from ${JSON.stringify(host)};
    import {createOpenAIChatProvider} from ${JSON.stringify(factory)};
    const received=[], events=[];
    let requestEntered, responseClosed;
    const entered=new Promise(resolve=>{requestEntered=resolve;});
    const responseStopped=new Promise(resolve=>{responseClosed=resolve;});
    const handleRequest=async(req,res)=>{
      let wire='';for await(const chunk of req)wire+=chunk;
      const request=JSON.parse(wire);received.push(request);
      assert.equal(req.url,'/v1/chat/completions');
      assert.equal(req.headers.authorization,'Bearer not-an-external-secret');
      assert.equal(request.model,'fixture-chat');
      assert.notEqual(request.stream,true);
      if (${cancelEntered}) {
        // Hold this real request until the original public cancellation stops
        // its actual transport. The server never manufactures a response.
        res.once('close',responseClosed);requestEntered();return;
      }
      if (${responseLost}) {
        // The server has received the complete actual request. Losing its
        // response is not evidence of non-send or permission for another call.
        req.socket.destroy();return;
      }
      const input=JSON.parse(request.messages[1].content);
      if (${httpStatus} !== 200) {
        assert.deepEqual(input,{text:'first'});
        res.statusCode=${httpStatus};res.setHeader('content-type','application/json');
        res.end(JSON.stringify({error:{message:'authored provider refusal',type:'fixture_error',code:'fixture_error'}}));
        return;
      }
      const value=Object.hasOwn(input,'text')?{answer:true}:{label:'exact-label'};
      assert.deepEqual(input,Object.hasOwn(input,'text')?{text:'first'}:{quantity:7});
      res.setHeader('content-type','application/json');res.setHeader('x-request-id','http-'+received.length);
      res.end(JSON.stringify({id:'http-'+received.length,object:'chat.completion',created:1,model:'fixture-chat',
        choices:[{index:0,message:{role:'assistant',content:JSON.stringify(value)},finish_reason:'stop'}],
        usage:{prompt_tokens:2,completion_tokens:3,total_tokens:5}}));
    };
    let tlsOptions;
    if (${tls}) {
      const cert=await readFile('provider.crt','utf8');
      setDefaultCACertificates([...getCACertificates('default'),cert]);
      tlsOptions={cert,key:await readFile('provider.key')};
    }
    const server=${tls ? 'createTlsServer(tlsOptions,handleRequest)' : 'createServer(handleRequest)'};
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const keys=generateKeyPairSync('ed25519');
    if (${coldSaved || unknown}) {
      await writeFile('operator-private.fixture',keys.privateKey.export({type:'pkcs8',format:'pem'}),{mode:0o600});
      await writeFile('operator-public.fixture',keys.publicKey.export({type:'spki',format:'pem'}));
      await writeFile('endpoint.fixture',String(server.address().port));
    }
    const authorization={hostKey:{keyId:'http-host',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
      reviewers:[{keyId:'http-reviewer',reviewerId:'http-reviewer',principalId:userInfo().username,
        publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
      accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',account_id:'http-fixture',
        entries:[{entry_id:'fixture-only',outcome:'allow',principal:{all:true},connection:{all:true},resource:{all:true},
          operation:{all:true},exclusions:[]}]}),
      observe:(name,detail)=>events.push({name,detail})};
    const configureModelProvider=createOpenAIChatProvider({providerId:'models/http',modelId:'fixture-chat',
      apiKeyFile:'api-key.fixture',baseURL:'${tls ? 'https' : 'http'}://127.0.0.1:'+server.address().port+'/v1',
      generation:{temperature:0,topP:1,maxOutputTokens:100},
      budget:{maxCalls:2n,maxRows:2,maxTokens:1000n,maxCostUnits:100000n,maxDurationMs:1000n},
      observeEgress:()=>({classification:'public',region:'global',providerRetention:true,trainingUse:false})});
    const registerModelProviders=async(moon,context)=>{
      try{return await configureModelProvider(moon,context);}
      catch(cause){console.error('Original Model configuration failure',inspect(cause,{depth:8}));throw cause;}
    };
    const program=(task,field,value,type)=>({version:'actql/0.1',id:'normal-'+field,
      stages:[{id:'main',inputs:{},steps:[{values:{schema:{id:{type:'string',nullable:false},[field]:{type,nullable:false}},
        rows:[{id:'original-'+field,[field]:value}]},as:'input'},
        {assert_rows:{unique_by:['id']},as:'unique'},
        {infer:{contract:task,key:'id',input:{[field]:{field}}},as:'inferred'}],
        results:{answer:{from:'inferred',fields:['id','outcome','value']}}}],
      results:{answer:{from:{stage:'main',result:'answer'}}}});
    let client,primary;
    try{
      client=await connectEmbeddedLocal({mode:'local',owner:'local',installation:{directory:'.state',
        registerModelProviders,authorization}});
      const cases=[
        [0,['model-task:first','text','first','string'],{id:'original-text',outcome:'ok',value:{answer:true}}],
        [1,['model-task:second','quantity',7,'number'],{id:'original-quantity',outcome:'ok',value:{label:'exact-label'}}]];
      // Common's original raw non-2xx classification is provider_error for
      // each status. The SDK's rejected decoded projection cannot override it.
      if (${httpStatus} !== 200) {
        cases.length=1;cases[0][2]={id:'original-text',outcome:'failed:provider_error',value:null};
      }
      if (${unknown}) cases.length=1;
      for(const [index,args,expected]of cases){
        const submissionRef=client.newSubmission({nonce:'http-'+index});
        await writeFile('submission-'+index+'.json',JSON.stringify(submissionRef));
        const run=await client.start(program(...args),{submissionRef});
        await writeFile('run-'+index+'.json',JSON.stringify(run.ref));
        const waiting=run.wait();
        if (${cancelEntered}) {
          await entered;
          const before=await run.status();
          const cancelRef={...run.ref,cancelId:'entered-fixture-cancel',expectedRevision:before.control.revision};
          await writeFile('cancel-ref.json',JSON.stringify(cancelRef));
          const cancelled=await run.cancel({cancelId:cancelRef.cancelId,expectedRevision:cancelRef.expectedRevision,
            attemptId:'original-entered-fixture-cancel'});
          assert.equal(cancelled.kind,'accepted');assert.equal(cancelled.cancellation.kind,'accepted');
          assert.deepEqual(cancelled.cancellation.cancelRef,cancelRef);
          await writeFile('cancellation.json',JSON.stringify(cancelled.cancellation));
          assert.deepEqual(await run.lookupCancellation(cancelRef),{kind:'found',cancellation:cancelled.cancellation});
          await responseStopped;
        }
        const status=await waiting;
        assert.equal(status.status,${JSON.stringify(unknown ? 'needs_reconciliation' : 'succeeded')},
          inspect({status,events},{depth:8}));
        if (${cancelEntered}) assert.equal(status.control.cancellation_requested,true);
        if (!${unknown}) assert.deepEqual(await run.result('answer').all(),[expected]);
        const lookup=await client.lookupSubmission(submissionRef);
        assert.equal(lookup.kind,'ready');assert.deepEqual(lookup.admission.ref,run.ref);
      }
      assert.equal(received.length,cases.length);
      if (${httpStatus === 200 && !unknown}) assert.notDeepEqual(received[0].response_format.json_schema.schema,
        received[1].response_format.json_schema.schema);
    }catch(cause){primary=cause;console.error(inspect({cause,events,received},{depth:10}));}
    finally{
      try{await client?.close();}catch(cause){primary??=cause;}
      server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
    }
    const firstClose=observeOwnScopedStateFds([resolve('.state')]);
    if(primary!==undefined){console.error(inspect({firstClose}));throw primary;}
    assert.equal(firstClose.aliveAfterClose,true);
    assert.equal(firstClose.scopedStateFd0,true,inspect(firstClose));
    await assert.rejects(access('.state/publication/owner/owner.json'),{code:'ENOENT'});
    console.log(JSON.stringify({calls:received.length,tasks:${count},
      firstCloseReturned:true,aliveScopedFD0:true}));
  `;
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', script],
    {cwd: scratch.path, encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024});
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr + '\n' + child.stdout);
  assert.deepEqual(JSON.parse(child.stdout.trim().split('\n').at(-1)),
    {calls: count, tasks: count,
      firstCloseReturned: true, aliveScopedFD0: true});
  if (coldSaved || unknown) {
    // Distinct process on THIS new case's original state/ref, never a prior
    // failed state. No new submission, approval, recovery or provider call.
    const cold = `
      import assert from 'node:assert/strict';
      import {readFile,access} from 'node:fs/promises';
      import {resolve} from 'node:path';
      import {userInfo} from 'node:os';
      import {createServer} from 'node:http';
      import {createServer as createTlsServer} from 'node:https';
      import {getCACertificates,setDefaultCACertificates} from 'node:tls';
      import {inspect} from 'node:util';
      import {connectEmbeddedLocal} from ${JSON.stringify(host)};
      import {createOpenAIChatProvider} from ${JSON.stringify(factory)};
      import {observeOwnScopedStateFds} from ${JSON.stringify(fdObserver)};
      const port=Number(await readFile('endpoint.fixture','utf8'));
      let requests=0,egressChecks=0,client,primary;
      let tlsOptions;
      if (${tls}) {
        const cert=await readFile('provider.crt','utf8');
        setDefaultCACertificates([...getCACertificates('default'),cert]);
        tlsOptions={cert,key:await readFile('provider.key')};
      }
      const unexpectedRequest=(req,res)=>{requests++;req.resume();res.statusCode=500;res.end();};
      const server=${tls ? 'createTlsServer(tlsOptions,unexpectedRequest)' : 'createServer(unexpectedRequest)'};
      await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
      const authorization={hostKey:{keyId:'http-host',privateKey:await readFile('operator-private.fixture','utf8')},
        reviewers:[{keyId:'http-reviewer',reviewerId:'http-reviewer',principalId:userInfo().username,
          publicKey:await readFile('operator-public.fixture','utf8')}],
        accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',account_id:'http-fixture',
          entries:[{entry_id:'fixture-only',outcome:'allow',principal:{all:true},connection:{all:true},resource:{all:true},
            operation:{all:true},exclusions:[]}]})};
      const registerModelProviders=createOpenAIChatProvider({providerId:'models/http',modelId:'fixture-chat',
        apiKeyFile:'api-key.fixture',baseURL:'${tls ? 'https' : 'http'}://127.0.0.1:'+port+'/v1',
        generation:{temperature:0,topP:1,maxOutputTokens:100},
        budget:{maxCalls:2n,maxRows:2,maxTokens:1000n,maxCostUnits:100000n,maxDurationMs:1000n},
        observeEgress:()=>{egressChecks++;return {classification:'public',region:'global',providerRetention:true,trainingUse:false};}});
      try{
        client=await connectEmbeddedLocal({mode:'local',owner:'local',installation:{directory:'.state',
          registerModelProviders,authorization}});
        const ref=JSON.parse(await readFile('run-0.json','utf8'));
        const saved=await client.attach(ref);
        // Unknown has no invented Saved success. Its original status can be
        // observed without reconciliation, resubmission or provider lookup.
        if (!${unknown}) {
          // Original first Result comes BEFORE the explicit status operation.
          assert.deepEqual(await saved.result('answer').all(),[
            {id:'original-text',outcome:'ok',value:{answer:true}}]);
        }
        const state=await saved.status();
        assert.equal(state.status,${JSON.stringify(unknown ? 'needs_reconciliation' : 'succeeded')});
        if (${cancelEntered}) {
          assert.equal(state.control.cancellation_requested,true);
          const cancelRef=JSON.parse(await readFile('cancel-ref.json','utf8'));
          const cancellation=JSON.parse(await readFile('cancellation.json','utf8'));
          assert.deepEqual(await saved.lookupCancellation(cancelRef),{kind:'found',cancellation});
        }
        const submissionRef=JSON.parse(await readFile('submission-0.json','utf8'));
        const lookup=await client.lookupSubmission(submissionRef);
        assert.equal(lookup.kind,'ready');assert.deepEqual(lookup.admission.ref,ref);
        assert.equal(requests,0);assert.equal(egressChecks,0);
      }catch(cause){primary=cause;console.error(inspect(cause,{depth:8}));}
      finally{
        try{await client?.close();}catch(cause){primary??=cause;}
        server.closeAllConnections();await new Promise(resolve=>server.close(resolve));
      }
      const close=observeOwnScopedStateFds([resolve('.state')]);
      if(primary!==undefined){console.error(inspect({close}));throw primary;}
      assert.equal(close.aliveAfterClose,true);assert.equal(close.scopedStateFd0,true,inspect(close));
      await assert.rejects(access('.state/publication/owner/owner.json'),{code:'ENOENT'});
      console.log(JSON.stringify({originalSavedFirst:${!unknown},unknownRetained:${unknown},
        requests,egressChecks,firstCloseReturned:true,aliveScopedFD0:true}));
    `;
    const reopened = spawnSync(process.execPath, ['--input-type=module', '-e', cold],
      {cwd: scratch.path, encoding: 'utf8', timeout: 180000, maxBuffer: 4 * 1024 * 1024});
    assert.ifError(reopened.error);
    assert.equal(reopened.status, 0, reopened.stderr + '\n' + reopened.stdout);
    assert.deepEqual(JSON.parse(reopened.stdout.trim().split('\n').at(-1)),
      {originalSavedFirst:!unknown,unknownRetained:unknown,requests:0,egressChecks:0,
        firstCloseReturned:true,aliveScopedFD0:true});
  }
  scratch.passed();
}

test('normal OpenAI factory executes two unequal Tasks through actual Host and HTTP',
  () => normalHttpFixture());
test('normal OpenAI original Saved reads first in a distinct process without another request',
  () => normalHttpFixture({coldSaved:true}));

for (const httpStatus of [401, 429, 503]) {
  test(`normal OpenAI actual HTTP ${httpStatus} retains original failure rows without retry`,
    () => normalHttpFixture({httpStatus}));
}

test('normal OpenAI actual response loss remains Unknown across process reopen without resend',
  () => normalHttpFixture({transport:'response-lost'}));

test('normal OpenAI actual entered cancellation preserves Unknown and its original control across reopen',
  () => normalHttpFixture({cancelEntered:true}));

test('normal OpenAI actual TLS and original Saved first keep the same endpoint without resend',
  () => normalHttpFixture({coldSaved:true,tls:true}));
