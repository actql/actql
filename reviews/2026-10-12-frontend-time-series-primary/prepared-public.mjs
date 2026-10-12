// Run only in the explicitly assigned shared Heavy window.
import assert from 'node:assert/strict';
import {isAbsolute,relative,resolve} from 'node:path';
import {checkoutState} from '../../scripts/packed-client-packages.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const [mode,source,directory,...extra]=process.argv.slice(2);
assert.ok(['--producer','--consumer'].includes(mode));
assert.equal(extra.length,0);assert.match(source,/^[a-f0-9]{40}$/u);assert.ok(isAbsolute(directory));
const state=checkoutState(process.cwd());assert.equal(state.revision,source);assert.equal(state.clean,true);
assert.ok(relative(resolve(process.cwd()),resolve(directory)).startsWith('../'));
const steps=mode==='--producer'
  ? [{name:'Normal five-package time-series source producer',command:'node',args:['scripts/packed-client-packages.mjs',directory]}]
  : [{name:'Installed Local HTTPS time-series nine normal seven refusal cases and retained reread',command:'node',
    args:['scripts/test-packed-public-query.mjs','--time-series-primary-only','--keep-artifacts'],env:{ACTQL_PACKED_CLIENT_PACKAGES:directory}}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:true,timeoutSeconds:300,graceSeconds:5,steps});
