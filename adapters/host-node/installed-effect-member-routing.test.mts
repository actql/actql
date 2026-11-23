// Pure installed routing and actual row factory with explicit Core ports.
// This is not an admitted Request, physical send or ordinary STORE acceptance.
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {installedEffectFor} from './installed-effect-inventory.mjs';
import {createInstalledRowEffect,composeInstalledRowEffectOwners} from './installed-row-effect.mjs';

const cid=(digit: string)=>'sha256:'+digit.repeat(64);
const descriptor=(index: number | undefined)=>Object.freeze({effectId:`save${index}`,kind:'create' as const,
  target:'connector://fixture/records',mappingRef:'mapping:fixture/records',mappingCid:cid('a')});
test('17 definitions at one installed owner route directly without unfunded owner composition',()=>{
  const owner=Object.freeze({effectSelectors:Object.freeze([descriptor(undefined)])});
  const selector: Omit<ReturnType<typeof descriptor>, 'effectId'> & {effectId?: string} = {...owner.effectSelectors[0]};
  delete selector.effectId;
  const original=Object.freeze({...owner,effectSelectors:Object.freeze([Object.freeze(selector)])});
  assert.strictEqual(installedEffectFor({effects:[original]},Array.from({length:17},(_,i)=>descriptor(i))),original);
});

test('standalone legacy composition preserves its 16-definition constructor envelope',async t=>{
  const root=await mkdtemp(join(tmpdir(),'actql-legacy-effect-members-'));
  t.after(()=>rm(root,{recursive:true,force:true}));
  const unused=()=>assert.fail('No provider, authorization or dispatch in routing');
  const moon={strategyRemoteManagedOutputEvidenceKind:()=> 'fixture-unused'};
  const effects: object[]=[];
  for(let index=0;index<17;index++)effects.push(await createInstalledRowEffect({moon,
    environmentWire:'{}',connectorId:'fixture',connectorRegistration:'fixture',connectorRevision:'fixture/0.1',
    connection:'fixture',runtimeBundleCid:cid('b'),bindingCid:cid('c'),ledgerRoot:root,
    mappings:[{resource:'records',mappingRef:'mapping:fixture/records',mappingCid:cid('a'),
      body:JSON.stringify({mapping_contract_cid:cid('a'),target_ref:'connector://fixture/records',
        minimum_approval:'required',permission_rules:[{effect_kind:'create',permissions:['write']}]})}],
    site:{issueReadGrant:unused,issueEffectGrant:unused},authorization:{authorize:unused},
    driver:{kinds:['create'],prepareRequest:unused,requestFacts:unused,writeOperation:unused,
      send:unused,project:unused,footprint:unused}}));
  assert.throws(()=>composeInstalledRowEffectOwners(effects,Array.from({length:17},(_,i)=>descriptor(i)),'{}'),
    {code:'InstalledEffectSetOwnerMismatch'});
});
