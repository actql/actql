// The ordinary installed Row Effect validates the original refresh and claim
// before requesting mutation authority. No separate Salesforce dispatcher is used.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {effectHost, effectProgram, installedEffect} from './installed-salesforce-effect.fixture.mjs';

test('copied current and foreign frontier claims refuse before use, then the original row applies once',
  {timeout: 20_000}, async t => {
    const installation = await installedEffect(t, {writeOperation: 'create',
      writes: [{resource: 'Test_Record__c', kind: 'createFromResult', sources: [
        {target: 'External_Key__c', field: 'id', nullBehavior: 'reject'},
        {target: 'Name', field: 'id', nullBehavior: 'reject'},
      ]}]});
    let resolutions = 0;
    const resolveSecret = installation.options.resolveSecret;
    const installed = await installation.load({}, {resolveSecret(...args) {
      resolutions++;
      return Reflect.apply(resolveSecret, installation.options, args);
    }});
    let checked = false;
    const host = await effectHost(t, installation, join(installation.root, 'host'),
      {effect: installed, wrapStage: stage => ({...stage, apply: {...stage.apply,
        bindDispatch(binding) {
          const dispatch = stage.apply.bindDispatch(binding);
          return async row => {
            assert.equal(checked, false);
            const before = {requests: installation.org.seen.length, resolutions};
            // Equal DATA is not the original current refresh; a foreign key
            // is not the frontier's original claim, even with every other
            // field retained. Neither attempt may resolve a secret or send.
            await assert.rejects(dispatch({...row,
              currentPreflight: {...row.currentPreflight}}),
            {code: 'InvalidInstalledRowEffectRoute'});
            assert.deepEqual({requests: installation.org.seen.length, resolutions}, before);
            await assert.rejects(dispatch({...row, claim: {...row.claim, key: {}}}),
              {code: 'InvalidInstalledRowEffectDispatch'});
            assert.deepEqual({requests: installation.org.seen.length, resolutions}, before);
            checked = true;
            return dispatch(row);
          };
        },
      }})});
    const [mapping] = installed.mappings;
    const result = await host.run(effectProgram({save: {create: {target: mapping.target,
      mapping: mapping.mappingRef, from: {result: 'rows'}}}}, [{id: 'original-frontier'}]),
    'original-frontier');
    assert.equal(checked, true);
    assert.equal(result.started.value.status, 'published');
    const writes = installation.org.seen.filter(entry => entry.method === 'POST');
    assert.equal(writes.length, 1);
    assert.equal(writes[0].body,
      '{"External_Key__c":"original-frontier","Name":"original-frontier"}');
  });
