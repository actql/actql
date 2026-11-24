// Actual current public facade and SDK protocol, with an explicit Host DATA
// response. No private connect reconstruction or obsolete selected hook.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {registerHooks} from 'node:module';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import * as node from '@actql/node';

const root = fileURLToPath(new URL('../', import.meta.url));
const profile = (mode:'remote'|'local') => ({version:'actql-client-host/0.1', mode, owner:mode,
  durability:'durable', scopeRef:'node-current-route', capabilities:[], limits:{
    maxReadWireBytes:4096,maxRowWireBytes:1024,maxRowRetainedValueBytes:1024,
    maxRetainedValueBytes:4096,maxRows:10,maxBatchRows:2,maxBatchRetainedValueBytes:2048}});

test('public Node import keeps SDK lazy and preserves original error classes', () => {
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', `
import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
const original = new URL('./packages/sdk/index.mjs', import.meta.url).href;
let loads=0;
const hook=registerHooks({load(url,context,next){if(url===original)loads++;return next(url,context);}});
try {
  const node=await import('./packages/node/index.mjs');
  assert.equal(loads,0,'importing the Node facade must not initialize the SDK');
  await assert.rejects(node.connect({mode:'remote',endpoint:'not-an-origin',token:'fixture'}),
    error=>error instanceof node.ClientError&&error.code==='InvalidConnectionEndpoint');
  assert.equal(loads,1,'the first actual SDK route loads its original module');
  const sdk=await import('./packages/sdk/index.mjs');
  assert.strictEqual(node.ClientError,sdk.ClientError);
  assert.strictEqual(node.RequestHeld,sdk.RequestHeld);
} finally {hook.deregister();}
  `], {cwd:root,encoding:'utf8',timeout:10000,maxBuffer:1024*1024});
  assert.equal(result.error,undefined);
  assert.equal(result.signal,null);
  assert.equal(result.status,0,result.stderr);
});

for (const mode of ['remote','local'] as const) {
  test(`actual ${mode} SDK route never acquires Local or reads embedded installation/profile`, async t => {
    let localResolutions=0,credentials=0;
    const packets:unknown[]=[];
    const hook=registerHooks({resolve(specifier,context,next){
      if(specifier==='@actql/local-node'||specifier.startsWith('@actql/local-node/'))localResolutions++;
      return next(specifier,context);
    }});
    t.mock.method(globalThis,'fetch',async(url:unknown,options:{body:string;headers:{authorization:string}})=>{
      assert.equal(String(url),'https://host.example/actql/client/0.1/connect');
      assert.equal(options.headers.authorization,'Bearer original');
      packets.push(JSON.parse(options.body) as unknown);
      return Response.json(profile(mode));
    });
    const raw={mode,...(mode==='local'?{owner:'local' as const}:{}),endpoint:'https://host.example/',
      token(){credentials++;return 'original';}};
    Object.defineProperties(raw,{
      installation:{get(){assert.fail('No connected-route installation read');}},
      profile:{get(){assert.fail('No connected-route profile read');}},
    });
    try {
      const client=await node.connect(raw as node.NodeConnectionOptions);
      try {
        assert.equal(credentials,1);
        assert.equal(localResolutions,0);
        assert.deepEqual(packets,[{connection:{mode,owner:mode,consentRefs:[],runners:[]}}]);
      } finally {await client.close();}
    } finally {hook.deregister();}
  });
}

test('connection strings retain the actual SDK route and original credential callback', async t => {
  let localResolutions=0,credentials=0;
  const packets:unknown[]=[];
  const hook=registerHooks({resolve(specifier,context,next){
    if(specifier==='@actql/local-node'||specifier.startsWith('@actql/local-node/'))localResolutions++;
    return next(specifier,context);
  }});
  t.mock.method(globalThis,'fetch',async(url:unknown,options:{body:string;headers:{authorization:string}})=>{
    assert.equal(String(url),'https://host.example/actql/client/0.1/connect');
    assert.equal(options.headers.authorization,'Bearer original-string');
    packets.push(JSON.parse(options.body) as unknown);
    return Response.json({...profile('remote'),workspaceId:'workspace'});
  });
  try {
    const client=await node.connect('actql://host.example/workspace',{token(){credentials++;return 'original-string';}});
    try {
      assert.equal(credentials,1);
      assert.equal(localResolutions,0);
      assert.deepEqual(packets,[{connection:{mode:'remote',owner:'remote',workspaceId:'workspace',consentRefs:[],runners:[]}}]);
    } finally {await client.close();}
  } finally {hook.deregister();}
});

test('existing second-argument rejection precedes every object observation', async () => {
  const raw=new Proxy({}, {get(){assert.fail('NoRawGetter');},ownKeys(){assert.fail('NoRawCopy');},
    getOwnPropertyDescriptor(){assert.fail('NoRawDescriptor');},getPrototypeOf(){assert.fail('NoRawPrototype');}});
  await assert.rejects((node.connect as (input:unknown,second:unknown)=>Promise<unknown>)(raw,{}),
    error=>error instanceof node.ClientError&&error.code==='InvalidConnectionOptions');
});
