import test from 'node:test';import assert from 'node:assert/strict';
import {createExplorerGateway} from './gateway.mjs';import {createExplorerBrowserSource} from './browser-source.mjs';
import {checkpointFixture,reviewFixture} from '../explorer-ui/checkpoint-review.fixture.mjs';
const origin='http://127.0.0.1:43210';
const reference=()=>({checkpointCid:checkpointFixture().checkpointCid,reviewProjectionCid:checkpointFixture().reviewProjectionCid});
function harness(overrides={}){const calls=[],client={attach(){assert.fail('not a Run join');},
 async checkpoints(options){calls.push(['list',options]);return{items:[checkpointFixture()],next:'opaque-original-cursor'};},
 async reviewCheckpoint(original,limits){calls.push(['review',original,limits]);return reviewFixture();},
 resolveCheckpoints(){assert.fail('no answer');},start(){assert.fail('no start');},...overrides};
 const gateway=createExplorerGateway({client,origin});let cookie;
 const raw=async(path,body,headers={})=>gateway.fetch(new Request(origin+path,{method:'POST',headers:{Host:'127.0.0.1:43210',Origin:origin,
 'Content-Type':'application/json',...headers},body:JSON.stringify(body)}));
 const fetch=async(url,options)=>{const answer=await gateway.fetch(new Request(url,{...options,headers:{...options.headers,
 Host:'127.0.0.1:43210',Origin:origin,...(cookie?{Cookie:cookie}:{})}}));
 if(answer.headers.get('set-cookie'))cookie=answer.headers.get('set-cookie').split(';')[0];return answer;};
 const source=createExplorerBrowserSource({origin,fetch});return {gateway,source,raw,calls,
 async connect(){return source.connect(gateway.issueBootstrap().bootstrap);},
 async session(){const response=await raw('/api/session',{bootstrap:gateway.issueBootstrap().bootstrap});return {body:await response.json(),cookie:response.headers.get('set-cookie').split(';')[0]};}};
}
test('Gateway exposes only existing separately authorized list/review reads without Run lookup',async()=>{
 const h=harness();try{const cap=await h.connect();assert.equal(cap.checkpointList,true);assert.equal(cap.checkpointReview,true);
 const page=await h.source.checkpoints();assert.equal(page.items.length,1);
 const read=await h.source.reviewCheckpoint(reference());assert.equal(read.artifactCid,page.items[0].reviewProjectionCid);
 assert.deepEqual(h.calls,[['list',{limit:32}],['review',checkpointFixture().checkpointCid,{maxBytes:65536}]]);
 }finally{h.source.close();h.gateway.close();}
});
test('CSRF, nonclosed input and invalid Checkpoint refuse before separate SDK reader',async()=>{
 const h=harness();try{const session=await h.session();const headers={Cookie:session.cookie,'X-Actql-CSRF':session.body.csrf};
 assert.equal((await h.raw('/api/read/checkpoints',{}, {Cookie:session.cookie})).status,403);
 assert.equal((await h.raw('/api/read/checkpoints',{runRef:{}},headers)).status,400);
 assert.notEqual((await h.raw('/api/read/checkpoint-review',{checkpoint:{...reference(),approved:true}},headers)).status,200);
 assert.equal((await h.raw('/api/control/checkpoint-review',{checkpoint:reference()},headers)).status,404);
 assert.deepEqual(h.calls,[]);
 }finally{h.gateway.close();}
});
test('late review and current denial never disclose old-scope artifact and do not retry',async()=>{
 let release,calls=0;const ready=new Promise(resolve=>release=resolve);
 const h=harness({async reviewCheckpoint(){calls++;return ready;}});try{await h.connect();const pending=h.source.reviewCheckpoint(reference());
 await new Promise(resolve=>setImmediate(resolve));h.source.close();h.gateway.invalidateScope();release(reviewFixture());
 await assert.rejects(pending);assert.equal(calls,1);
 }finally{release(reviewFixture());h.gateway.close();}
 const deny=harness({async reviewCheckpoint(){throw Error('private credential path');}});
 try{await deny.connect();await assert.rejects(deny.source.reviewCheckpoint(reference()),error=>!error.message.includes('private credential'));}
 finally{deny.gateway.close();}
});
test('missing SDK methods remain unavailable and a forged review cannot replace selected identity',async()=>{
 const missing=harness({checkpoints:undefined,reviewCheckpoint:undefined});try{const capabilities=await missing.connect();assert.equal(capabilities.checkpointList,false);
 assert.equal(capabilities.checkpointReview,false);await assert.rejects(missing.source.checkpoints(),{code:'ExplorerCapabilityUnavailable'});
 await assert.rejects(missing.source.reviewCheckpoint(reference()),{code:'ExplorerCapabilityUnavailable'});
 assert.deepEqual(missing.calls,[]);}finally{missing.gateway.close();}
 const h=harness({async reviewCheckpoint(){return{...reviewFixture(),artifactCid:'sha256:'+'f'.repeat(64)};}});
 try{await h.connect();await assert.rejects(h.source.reviewCheckpoint(reference()));}finally{h.gateway.close();}
});
