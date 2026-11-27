import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {originalSdkCallOptions} from './_internal/model-port.mjs';
import {prepareSelectedChat} from './selected-chat.fixture.mjs';
import {pollSdkPreparation, sdkPreparedRequest, cleanupSdkPreparation}
  from './_internal/intercepted-request.mjs';

const selector = 'original-selector';
const schema = {type:'object',properties:{answer:{type:'string'}},required:['answer'],additionalProperties:false};
const prompt = [{role:'system',content:'Original instructions'},
  {role:'user',content:[{type:'text',text:'e\u0301\r\n'}]}];
const responseFormat = {type:'json',name:'actql_output',schema};
const limits = {maxRequestBytes:1000,maxHeaderBytes:4096,maxHeaders:16};
const projection = (seed = -7n, tokens = 16n) => ({_0:selector,_1:0.25,_2:0.875,_3:tokens,_4:seed});
function prepare(generation, notify=()=>{}) {
  return prepareSelectedChat({...limits, selector, modelId:'gpt-4.1-nano',
    baseURL:'https://fixture.invalid/v1',apiKey:'fixture-only',notify,
    options:originalSdkCallOptions(generation,prompt,responseFormat,'RegisteredSdkGenerationUnsupported')});
}
async function ready(handle) {
  for (let n = 0; n < 30; n++) {
    if (pollSdkPreparation(handle).kind === 'ready') return;
    await turn();
  }
  assert.fail('Original SDK request did not become ready');
}
async function retire(handle) {
  for (let n = 0; n < 30; n++) {
    if (cleanupSdkPreparation(handle)) return;
    await turn();
  }
  assert.fail('Original SDK preparation did not retire');
}

test('original generation values reach the real pinned SDK without defaults or network', async t => {
  const ambient = globalThis.fetch;
  let fetches = 0;
  globalThis.fetch = () => { fetches++; assert.fail('Ambient network'); };
  t.after(() => { globalThis.fetch = ambient; });
  const handle = prepare(projection());
  t.after(() => retire(handle));
  await ready(handle);
  assert.deepEqual(JSON.parse(sdkPreparedRequest(handle).body), {
    model: 'gpt-4.1-nano', temperature: 0.25, top_p: 0.875,
    max_tokens: 16, seed: -7,
    response_format:{type:'json_schema',json_schema:{name:'actql_output',schema,strict:true}},
    messages:[{role:'system',content:'Original instructions'},{role:'user',content:'e\u0301\r\n'}],
  });
  assert.equal(fetches, 0);
});

test('absent seed stays absent and zero seed is not replaced by an SDK default', async () => {
  for (const seed of [undefined, 0n]) {
    const value = projection();
    value._4 = seed;
    const handle = prepare(value);
    try {
      await ready(handle);
      const body = JSON.parse(sdkPreparedRequest(handle).body);
      assert.equal(Object.hasOwn(body, 'seed'), seed !== undefined);
      if (seed !== undefined) assert.equal(body.seed, 0);
    } finally { await retire(handle); }
  }
});

test('both safe seed endpoints preserve exact original integers', async () => {
  for (const seed of [-9_007_199_254_740_991n, 9_007_199_254_740_991n]) {
    const handle = prepare(projection(seed));
    try {
      await ready(handle);
      assert.equal(JSON.parse(sdkPreparedRequest(handle).body).seed, Number(seed));
    } finally { await retire(handle); }
  }
});

test('pinned MoonBit unsigned Int64 backing preserves a negative authored seed', async () => {
  const handle = prepare(projection(18_446_744_073_709_551_609n));
  try {
    await ready(handle);
    assert.equal(JSON.parse(sdkPreparedRequest(handle).body).seed, -7);
  } finally { await retire(handle); }
});

test('unsupported Int64 values refuse instead of rounding before SDK preparation', () => {
  let wakes = 0;
  for (const value of [projection(-9_007_199_254_740_992n),
    projection(9_007_199_254_740_992n), projection(null),
    projection(-7n, 9_007_199_254_740_992n), projection(-7n, 0n),
    projection(18_446_744_073_709_551_616n)]) {
    assert.throws(() => prepare(value,()=>{wakes++;}),
      {message:'RegisteredSdkGenerationUnsupported'});
  }
  assert.equal(wakes, 0);
});
