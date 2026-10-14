import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as turn} from 'node:timers/promises';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {createOpenAI} from '@ai-sdk/openai';
import {interceptSdkRequest, pollSdkPreparation, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportRawObservation,
  pollSdkDecode, takeSdkDecodedResult, cleanupSdkPreparation} from
  './_internal/intercepted-request.mjs';

async function until(read, accept) {
  for (let i=0;i<60;i++) {
    const value=read();
    if (accept(value)) return value;
    await turn();
  }
  assert.fail('Original private SDK settlement was not observed');
}

test('pinned SDK raw-only retirement retains its actual terminal provenance and temporary network scratch', async t=>{
  // Source-bound physical diagnostic only. Capturing the terminal below adds
  // one test-owned alias/callback. It is not a production heap upper bound,
  // original Store receipt, Common answer, numerical grant or public Run.
  const utils=new URL('./node_modules/@ai-sdk/provider-utils/dist/index.js',import.meta.url);
  assert.equal(createHash('sha256').update(readFileSync(utils)).digest('hex'),
    '558a268f4bf88f7aa39caae20cee29e9ade99448bd3bf87af123a2239be1b135');
  const endpoint='https://fixture.invalid/v1/chat/completions';
  let terminal, sends=0, networkScratch=0;
  const handle=interceptSdkRequest({endpoint,maxRequestBytes:1000,
    maxHeaderBytes:4096,maxHeaders:16,notify(){},
    runSdk:(fetch,abortSignal)=>createOpenAI({baseURL:'https://fixture.invalid/v1',
      apiKey:'fixture-only',fetch}).chat('gpt-4.1-nano').doGenerate({abortSignal,
        prompt:[{role:'user',content:[{type:'text',text:'Original é\r\n'}]}],
        responseFormat:{type:'json'},maxOutputTokens:16,
      }).catch(error=>{terminal=error;throw error;}),
  });
  const OriginalSet=globalThis.Set;
  t.after(async()=>{
    globalThis.Set=OriginalSet;
    await until(()=>cleanupSdkPreparation(handle),Boolean);
  });
  await until(()=>pollSdkPreparation(handle),v=>v.kind==='ready');
  const bytes=new TextEncoder().encode('{"original":"é\\r\\n"}');
  const response=new Response(bytes);
  prepareSdkTransport(handle,{responseMode:'raw-only',
    responseLimits:{maxBytes:2048,maxChunkBytes:512,maxChunks:16,
      maxHeaderBytes:128,observedHeaders:['content-type']},
    fetch(){sends++;return response;},observeAt:()=> '2026-10-14T00:00:00.000Z'});
  // Count only the selected SDK source callsite after request normalization
  // and fixed transport preparation. Stack capture and this subclass are
  // diagnostic overhead, excluded from production byte/GC claims.
  globalThis.Set=class extends OriginalSet {
    constructor(...args) {
      super(...args);
      if (/at findNetworkError .*@ai-sdk\/provider-utils\/dist\/index\.js/u
        .test(new Error().stack)) networkScratch++;
    }
  };
  startSdkTransport(handle);
  await until(()=>pollSdkTransport(handle),v=>v.kind==='response');
  assert.deepEqual(await until(()=>pollSdkDecode(handle),v=>v.kind!=='pending'),
    {kind:'retired'});
  globalThis.Set=OriginalSet;
  // postToApi passes the intentional Symbol through handleFetchError; it
  // still creates findNetworkError's visited Set. Neither fact authorizes
  // discarding raw or refunding SDK/Promise/cleanup workspace early.
  assert.equal(typeof terminal,'symbol');
  assert.equal(terminal.description,'ActQLSdkRawConsumerRetired');
  assert.equal(networkScratch,1);
  assert.deepEqual(sdkTransportRawObservation(handle).body,bytes);
  assert.equal(sdkTransportRawObservation(handle).transportComplete,true);
  assert.equal(sends,1);
  assert.throws(()=>takeSdkDecodedResult(handle),{code:'SdkDecodedResultUnavailable'});
  assert.throws(()=>startSdkTransport(handle),{code:'SdkTransportStartRefused'});
});
