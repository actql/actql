import assert from 'node:assert/strict';
import {mkdir, mkdtemp, readFile, readdir} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {createRetainedGraphAuthorization} from './fixtures/retained-graph-observer.mjs';
import {graphSnapshotFailureStore} from './fixtures/graph-snapshot-failure-store.mjs';
import {graphGraftSourceSuccesses} from './fixtures/graph-graft-source-input.mjs';
import {graphReachSourceSuccesses} from './fixtures/graph-reach-source-input.mjs';

const packed = process.env.ACTQL_GRAPH_PACKED === '1';
const {connect} = await import(packed ? '@actql/sdk' : '../packages/sdk/index.mjs');
const {connectEmbeddedLocal, openInstalledRemoteHttpHost} = await import(packed
  ? new URL('./adapters/host-node/embedded-local.mjs', import.meta.resolve('@actql/local-node'))
  : '../adapters/host-node/embedded-local.mjs');
const {createLocalRetainedStore} = await import(packed
  ? new URL('./adapters/store-local/files.mjs', import.meta.resolve('@actql/local-node'))
  : '../adapters/store-local/files.mjs');
const scratch = new URL(packed ? './failure-state/' : '../_build/graph-public-failure/', import.meta.url);
await mkdir(scratch, {recursive:true});

// Both retained snapshot lanes are shared: Graft/Mean produce Graph material;
// Reach/Shortest produce Relation material. Do not repeat their full normal
// operation matrix merely to test the same Store failure/cleanup ownership.
const cases = [
  {family:'carrier', failure:'seal', key:'task-3', sample:graphGraftSourceSuccesses[0]},
  {family:'relation', failure:'append', key:'relation-task-3', sample:
    graphReachSourceSuccesses.find(sample => sample.name === 'graph-reach-json-connected-out')},
];
assert(cases.every(value => value.sample?.format === 'json'));
for (const mode of ['local', 'remote']) for (const scenario of cases) {
  test(`Graph ${scenario.family} ${scenario.failure} keeps public cleanup custody (${mode})`,
    {timeout:60_000}, async t => {
      const directory = await mkdtemp(new URL(`${scenario.family}-${mode}-`, scratch));
      t.diagnostic(`Public Graph failure evidence: ${directory}`);
      const faults = graphSnapshotFailureStore({createStore:createLocalRetainedStore,
        targetKey:scenario.key,failure:scenario.failure});
      const physical = [];
      const faultInjection = Object.assign(async (name, detail) => {
        if (['physical_start_reserved','local_compute_advanced','computed'].includes(name)) {
          physical.push({name,task:detail?.task});
        }
      }, {localSnapshotStoreFactory:details => faults.factory(details)});
      const authorization = {...createRetainedGraphAuthorization(),faultInjection};
      let client, host, server;
      const closeOwner = () => mode === 'local' ? client.close() : host.close();
      t.after(async () => {
        faults.permitCleanup();
        // The original installed Host must settle its own cleanup; direct
        // fixture reclamation cannot stand in for this responsibility.
        if (mode === 'local' ? client !== undefined : host !== undefined) await closeOwner();
        if (mode !== 'local' && client !== undefined) await client.close();
        if (server) await new Promise((resolve,reject) =>
          server.close(error => error ? reject(error) : resolve()));
      });
      if (mode === 'local') {
        client = await connectEmbeddedLocal({mode,owner:'local',installation:{directory,authorization}});
      } else {
        host = await openInstalledRemoteHttpHost({directory,authorization,
          authenticate:header => header === 'Bearer synthetic-graph-failure' ? userInfo().username : undefined});
        let material;
        if (packed) {
          const read = name => readFile(new URL(`./tls/${name}`, import.meta.url));
          material = {ca:await read('ca.crt'),siteKey:await read('site.key'),siteCertificate:await read('site.crt')};
        } else {
          const {certificates} = await import('../adapters/site-node/https-agent-harness.mjs');
          const tlsDirectory = await mkdtemp(new URL('tls-', scratch));
          material = await certificates(tlsDirectory);
        }
        const previousCAs = getCACertificates('default');
        setDefaultCACertificates([...previousCAs,material.ca.toString('utf8')]);
        t.after(() => setDefaultCACertificates(previousCAs));
        server = createServer({key:material.siteKey,cert:material.siteCertificate},host.handler);
        await new Promise((resolve,reject) => {
          server.once('error',reject);server.listen(0,'127.0.0.1',resolve);
        });
        client = await connect({mode,endpoint:`https://127.0.0.1:${server.address().port}/`,
          token:'synthetic-graph-failure'});
      }
      const document = JSON.parse(scenario.sample.text);
      document.id += `-${scenario.failure}-${mode}`;
      const source = JSON.stringify(document);
      const options = {format:'json',submissionRef:client.newSubmission({
        nonce:`graph-${scenario.family}-${scenario.failure}-${mode}`})};
      const run = await client.startSource(source, options);
      const state = await run.wait({signal:AbortSignal.timeout(15_000)});
      // The existing dispatch Owner cannot observe physical stop while its
      // retained cleanup is unresolved. execution.md requires unknown to stay
      // nonterminal; a known Store error alone must not fabricate Run failure.
      assert.equal(state.status,'needs_reconciliation',JSON.stringify(state));
      assert.deepEqual(state.next_action,{kind:'reconcile_run',reason:'execution_unknown'});
      assert.equal(state.control.physical_stop,'unknown');
      assert.equal(faults.leases.filter(value => value.key === scenario.key).length,1);
      const failure = faults.counts();
      assert.equal(failure.failedAppends,scenario.failure === 'append' ? 1 : 0);
      assert.equal(failure.lostSeals,scenario.failure === 'seal' ? 1 : 0);
      assert(failure.refusedCleanups > 0, 'the fault must reach pending physical cleanup');
      for (const name of Object.keys(scenario.sample.results)) {
        assert.equal(state.result_availability[name].state,'unavailable');
        await assert.rejects(run.result(name).all());
      }
      const target = faults.leases.find(value => value.key === scenario.key);
      assert(target.physical.status().reservedBytes > 0);
      assert.equal(target.physical.status().cleanupPending,true);
      const beforeRetry = structuredClone(physical);
      const leaseCount = faults.leases.length;
      const repeated = await client.startSource(source, options);
      assert.deepEqual(repeated.ref,run.ref);
      assert.equal((await repeated.status()).status,'needs_reconciliation');
      assert.deepEqual(physical,beforeRetry,'same failed submission must not dispatch or advance Compute');
      const observed = await run.reconcile();
      assert.equal(observed.status,'needs_reconciliation');
      assert.deepEqual(observed.next_action,{kind:'reconcile_run',reason:'execution_unknown'});
      assert.deepEqual(physical,beforeRetry,'reconciliation observes the retained execution without redispatch');
      await assert.rejects(closeOwner());
      assert(target.physical.status().reservedBytes > 0);
      assert.equal(target.physical.status().cleanupPending,true);
      assert.deepEqual(physical,beforeRetry,'failed close must not re-enter Compute');
      faults.permitCleanup();
      await closeOwner();
      assert.deepEqual(physical,beforeRetry,'cleanup retry must not re-enter Compute');
      assert.equal(faults.leases.length,leaseCount);
      for (const {physical:store} of faults.leases) {
        assert.equal(store.status().reservedBytes,0);
        assert.equal(store.status().cleanupPending,false);
      }
      assert.deepEqual(await readdir(`${directory}/carrier-snapshots`),[]);
    });
}
