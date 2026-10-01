import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';

// The same independent oracle runs against source and repository-external
// tarballs. The packed branch imports no checkout implementation or toolchain.
const packed = process.env.ACTQL_PROPERTY_GRAPH_PACKED === '1';
const {connect} = await import(packed ? '@actql/sdk' : '../packages/sdk/index.mjs');
const {connectEmbeddedLocal, openInstalledRemoteHttpHost} = await import(packed
  ? new URL('./adapters/host-node/embedded-local.mjs', import.meta.resolve('@actql/local-node'))
  : '../adapters/host-node/embedded-local.mjs');

const fixture = JSON.parse(await readFile(new URL('./fixtures/property-graph-parallel.program.json', import.meta.url), 'utf8'));
const scratch = new URL(packed ? './state/' : '../_build/property-graph-public-host/', import.meta.url);
await mkdir(scratch, {recursive:true});
const cid = value => 'sha256:' + createHash('sha256').update(canonicalText(value)).digest('hex');

// Independent definition preimage: source aliases become ordered occurrences;
// input data is an inline VALUES definition here, not a bound Artifact or Run.
const constructor = structuredClone(fixture.stages[0].steps[2].property_graph);
let occurrence = 0;
for (const family of ['nodes','edges']) for (const element of constructor[family]) {
  delete element.from;
  element.input_occurrence = occurrence++;
}
const expectedDomain = cid({constructor,
  producer_definitions:fixture.stages[0].steps.slice(0, 2)
    .map(step => ({body:{values:step.values},dependencies:[]})),
  version:'actql-property-graph-definition/0.1'});
const identity = (definition, key) => ({definition,domain:expectedDomain,
  key:[key],key_types:[{kind:'number'}]});

for (const mode of ['local','remote']) {
  test(`keyed constructor and TRAIL reach public Named Results through ${mode}`, {timeout:60_000}, async t => {
    const directory = await mkdtemp(new URL(`${mode}-`, scratch));
    t.diagnostic(`Retained Host regression evidence: ${directory}`);
    let host, server, client;
    if (mode === 'local') {
      client = await connectEmbeddedLocal({mode,owner:'local',installation:{directory}});
    } else {
      host = await openInstalledRemoteHttpHost({directory,
        authenticate:header=>header === 'Bearer synthetic-test-token' ? userInfo().username : undefined});
      t.after(async () => { await host.close(); });
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
      // Trust the synthetic fixture CA; TLS and hostname checks stay enabled.
      setDefaultCACertificates([...previousCAs,material.ca.toString('utf8')]);
      t.after(() => setDefaultCACertificates(previousCAs));
      server = createServer({key:material.siteKey,cert:material.siteCertificate},host.handler);
      await new Promise((resolve,reject) => {server.once('error',reject);server.listen(0,'127.0.0.1',resolve);});
      t.after(() => new Promise((resolve,reject) => server.close(error => error ? reject(error) : resolve())));
      client = await connect({mode,endpoint:`https://127.0.0.1:${server.address().port}/`,token:'synthetic-test-token'});
    }
    t.after(() => client.close());
    const run = await client.aql(canonicalText(fixture), {format:'json',requestId:`property-match-${mode}`});
    const state = await run.wait();
    assert.equal(state.status,'succeeded',JSON.stringify(state));
    const result = run.result('answer');
    const description = await result.describe();
    assert.deepEqual(description.columns,[{name:'key',contract:{type:'number',nullable:false}}]);
    assert.deepEqual(await result.all(),[{key:10},{key:11}]);
    assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(),[{key:10},{key:11}]);

    const trail = structuredClone(fixture);
    trail.id = 'property-graph-trail';
    trail.stages[0].steps.splice(3,1,
      {from:'g',match_nodes:{definition:'N',label:'Node',bindings:{identity:'element'},where:'true',fields:['element']},as:'seeds'},
      {from:'g',traverse:{start:{from:'seeds',id:'element'},direction:'out',min_hops:2,max_hops:2,path_mode:'trail',emit:'paths'},as:'paths'});
    trail.stages[0].results.out = {from:'paths',fields:['start_id','end_id','hop_count','node_ids','edge_ids']};
    const paths = await client.aql(canonicalText(trail), {format:'json',requestId:`property-trail-${mode}`});
    const pathsState = await paths.wait();
    assert.equal(pathsState.status,'succeeded',JSON.stringify(pathsState));
    const rows = await paths.result('answer').all();
    // Independent TRAIL oracle: two different self-loop keys can each be used
    // once; the two ordered two-hop permutations survive. No order is invented.
    const expected = [[10,11],[11,10]].map(keys => ({start_id:identity('N',1),end_id:identity('N',1),
      hop_count:2,node_ids:[identity('N',1),identity('N',1),identity('N',1)],edge_ids:keys.map(key=>identity('E',key))}));
    assert.deepEqual(rows.map(canonicalText).sort(),expected.map(canonicalText).sort());
  });
}
