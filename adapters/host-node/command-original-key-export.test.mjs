import assert from 'node:assert/strict';
import test from 'node:test';
import {moon,originalCommandKeyFixture} from './fixtures/command-original-key.fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {exportPinnedEffectInput,exportPinnedEffectLocalResult} from './effect-input-export.mjs';
import {advanceEffectCommandKey,retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';

test('actual original managed Command export completes keys before bytes and retains the same capture after temporary close',async()=>{
  const fixture=await originalCommandKeyFixture();
  const {execution,inputs,limits}=fixture;
  let key,plans=[],chunks=[],prepared=false;
  try{
    assert.throws(()=>checked(moon.clientProgramEffectProposalBegin(inputs,0,10,10000)),{code:'MoonBitHostFailure'});
    const summary=await exportPinnedEffectInput({moon,execution,inputs,memberIndex:0,limits,
      async prepareProposal(_exported,importing){
        key=checked(moon.clientProgramEffectManagedCommandKeyStart(inputs,0,importing,10000));
        assert(key);
        await advanceEffectCommandKey(moon,key,undefined,1);
        plans.push(checked(moon.clientProgramEffectProposalBeginWithKey(inputs,0,10,10000,key)));
        prepared=true;
      },
      onChunk(chunk){assert.equal(prepared,true);chunks.push(chunk);},
    });
    assert.equal(summary.rowCount,1);
    assert.deepEqual(JSON.parse(chunks.join('')),[{id:'one',value:'original'}]);
    plans.push(checked(moon.clientProgramEffectProposalBeginWithKey(inputs,0,10,10000,key)));
    moon.clientProgramReleaseEffectInputs(inputs);
    assert.throws(()=>checked(moon.clientProgramEffectProposalBeginWithKey(inputs,0,10,10000,key)),{code:'MoonBitHostFailure'});
  }finally{
    if(key!==undefined)await retireEffectCommandKeyWorkspace(()=>checked(moon.clientProgramEffectCommandKeyCleanup(key)));
    for(const plan of plans)moon.clientProgramEffectProposalCancel(plan);
    await fixture.close();
  }
});

test('actual original Command duplicate key fails its whole-input continuation before any exported bytes',async()=>{
  const fixture=await originalCommandKeyFixture({rows:[{id:'one',value:'original'},{id:'one',value:'different'}]});
  const {execution,inputs,limits}=fixture;
  let key,started=false,advanced=false,chunks=0;
  try{
    await assert.rejects(exportPinnedEffectInput({moon,execution,inputs,memberIndex:0,limits,
      async prepareProposal(_exported,importing){
        key=checked(moon.clientProgramEffectManagedCommandKeyStart(inputs,0,importing,10000));
        assert(key);started=true;
        try{await advanceEffectCommandKey(moon,key,undefined,1);}
        catch(error){advanced=true;await retireEffectCommandKeyWorkspace(()=>checked(moon.clientProgramEffectCommandKeyCleanup(key)),error);throw error;}
      },onChunk(){chunks++;},
    }),{code:'MoonBitHostFailure'});
    assert.equal(started,true);assert.equal(advanced,true);assert.equal(chunks,0);
  }finally{
    if(key!==undefined)await retireEffectCommandKeyWorkspace(()=>checked(moon.clientProgramEffectCommandKeyCleanup(key)));
    await fixture.close();
  }
});

test('actual local Result key bridge refuses a foreign pin inventory and keeps the legacy absent-key route',async()=>{
  for(const inputKey of [true,false]){
    const fixture=await originalCommandKeyFixture({inputKey});
    const {execution,inputs,limits,owned}=fixture;
    const foreign=checked(moon.clientProgramPinEffectSources(owned,2));
    let key;
    try{
      await exportPinnedEffectLocalResult({moon,execution,inputs,resultIndex:0,limits,
        async prepareProposal(exported){
          assert(exported);
          if(inputKey)assert.throws(()=>checked(moon.clientProgramEffectLocalCommandKeyStart(foreign,0,0,exported,limits,10000)),{code:'MoonBitHostFailure'});
          key=checked(moon.clientProgramEffectLocalCommandKeyStart(inputs,0,0,exported,limits,10000));
          assert.equal(key!==undefined,inputKey);
          await advanceEffectCommandKey(moon,key,undefined,7);
        },onChunk(){},
      });
    }finally{
      if(key!==undefined)await retireEffectCommandKeyWorkspace(()=>checked(moon.clientProgramEffectCommandKeyCleanup(key)));
      moon.clientProgramReleaseEffectInputs(foreign);await fixture.close();
    }
  }
});
