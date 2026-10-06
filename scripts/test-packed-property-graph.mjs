// Consume fresh public tarballs without a checkout or MoonBit lookup path.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {nodeTestArguments, assertTestExecution} from './test-execution.mjs';
import {CLIENT_PACKAGES, checkoutState, packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {certificates} from '../adapters/site-node/https-test-certificates.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const selectorDeriveOnly = process.argv.includes('--selector-derive-only');
const deltaApplicationOnly = process.argv.includes('--delta-application-only');
const deltaRelationOnly = process.argv.includes('--delta-relation-only');
const deltaDiffOnly = process.argv.includes('--delta-diff-only');
const unionOnly = process.argv.includes('--union-only');
const subtractionOnly = process.argv.includes('--subtraction-only');
if (process.argv.slice(2).some(argument=>!['--selector-derive-only',
  '--delta-application-only','--delta-relation-only','--delta-diff-only','--union-only','--subtraction-only'].includes(argument)) ||
  Number(selectorDeriveOnly) + Number(deltaApplicationOnly) + Number(deltaRelationOnly) + Number(deltaDiffOnly) + Number(unionOnly) + Number(subtractionOnly) > 1) {
  throw new Error('Unknown packed Property Graph selection');
}
const source = checkoutState(repository);
const scratch = await createOwnedScratch({
  parent:join(repository, '..', '.codex-scratch'),
  prefix:'property-graph-package-',label:'packed Property Graph',
  digests:()=>CLIENT_PACKAGES.map(name=>`actql-${name}-0.0.0-development.tgz`),
});
const root = scratch.path;
const environment = {...process.env,npm_config_cache:packedNpmCache(root)};
let sequence = 0;
async function run(command, args, cwd = root, env = environment, verifyTests = false) {
  const result = spawnSync(command,args,{cwd,env,encoding:'utf8',timeout:600_000});
  await writeFile(join(root,`${++sequence}.log`),`${result.stdout ?? ''}\n${result.stderr ?? ''}`);
  if (result.error || result.status !== 0) throw new Error(
    `${command} ${args.join(' ')} failed (status ${result.status}); evidence: ${root}`,
    {cause:result.error});
  if (verifyTests) assertTestExecution('node',command,args,result);
  return result.stdout;
}
for (const name of CLIENT_PACKAGES) await packedClientPackage({repository,name,destination:root,
  pack:()=>run('npm',['pack','--pack-destination',root,'--json'],join(repository,'packages',name))});
await writeFile(join(root,'package.json'),'{"private":true,"type":"module"}\n');
await run('npm',['install','--ignore-scripts','--no-save',...CLIENT_PACKAGES.map(name=>
  join(root,`actql-${name}-0.0.0-development.tgz`))]);
await mkdir(join(root,'fixtures'));
for (const name of ['property-graph-public-host.test.mjs','check-canonical-json.mjs',
  'fixtures/property-graph-parallel.program.json',
  'fixtures/property-graph-presence.program.json',
  'fixtures/property-graph-delta-application.mjs',
  'fixtures/property-graph-union.mjs',
  'fixtures/property-graph-subtraction.mjs',
  'fixtures/property-graph-definition-rows.program.json',
  'fixtures/property-graph-label-rows.program.json',
  'fixtures/property-graph-selector-derive.program.json',
  'fixtures/property-graph-traverse-nodes.expected.json']) await copyFile(join(repository,'scripts',name),join(root,name));
await copyFile(join(repository,'docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json'),
  join(root,'local-family-coverage.json'));
await mkdir(join(root,'tls'));
await certificates(join(root,'tls'));
const output = await run(process.execPath,nodeTestArguments([
  ...(selectorDeriveOnly ? ['--test-name-pattern','selector property derive'] : []),
  ...(deltaApplicationOnly ? ['--test-name-pattern','complete Delta application'] : []),
  ...(deltaRelationOnly ? ['--test-name-pattern','Delta Relation DISTINCT and GROUP'] : []),
  ...(deltaDiffOnly ? ['--test-name-pattern','Graph diff Delta survives'] : []),
  ...(unionOnly ? ['--test-name-pattern','Property Graph union preserves occurrences'] : []),
  ...(subtractionOnly ? ['--test-name-pattern','Property Graph subtraction preserves typed records'] : []),
  'property-graph-public-host.test.mjs']),root,
  {...environment,ACTQL_PROPERTY_GRAPH_PACKED:'1',
    PATH:[dirname(process.execPath),'/usr/bin','/bin'].join(':')},true);
const digests = {};
for (const name of CLIENT_PACKAGES) {
  const file = `actql-${name}-0.0.0-development.tgz`;
  digests[file] = 'sha256:' + createHash('sha256').update(await readFile(join(root,file))).digest('hex');
}
const acceptance = {
  version:'property-graph-packed-acceptance/0.1',node:process.version,
  source,
  packages:digests,paths:['embedded-local','remote-https'],
  selection:selectorDeriveOnly ? 'selector-derive' : deltaApplicationOnly ? 'delta-application'
    : deltaRelationOnly ? 'delta-relation' : deltaDiffOnly ? 'delta-diff' : unionOnly ? 'union' : subtractionOnly ? 'subtraction' : 'all',
  independentFixture:'fixtures/property-graph-parallel.program.json',
  presenceFixture:'fixtures/property-graph-presence.program.json',
  definitionFixture:'fixtures/property-graph-definition-rows.program.json',
  labelFixture:'fixtures/property-graph-label-rows.program.json',
  selectorDeriveFixture:'fixtures/property-graph-selector-derive.program.json',
  traversalFixture:'fixtures/property-graph-traverse-nodes.expected.json',
  assertions:subtractionOnly ? [
    'ordered binary borrowed occurrences preserve exact typed identities and source domain',
    'shared removal differs from explicit equality retention and number_sum remains addition',
    'induced endpoint closure and independent parallel-edge removal never rekey records',
    'independent Graph snapshot bytes CID and metadata after source invalidation and verified reload',
    'sparse Relation omission NULL values and original key components through real Store reload',
    'canonical initial Named Result and reattach order through public Local and HTTPS',
    'payload NULL strategy and endpoint conflicts fail without a partial Named Result',
    'list and extra-field subtraction refused before Run admission and physical work',
  ] : unionOnly ? [
    'ordered repeated Graph occurrences apply number_sum three times without identity conversion',
    'partial overlap restores the independent parallel edge without collapsing endpoints',
    'declaration-derived empty Graph and Relation schemas survive Store reload',
    'independent Graph snapshot bytes and CID with source invalidation and verified reload',
    'sparse Relation omission NULL values and original typed key components through real Store reload',
    'ordered initial Named Result and reattach through public Local and HTTPS',
    'shared edge endpoint conflict fails with no initial or reattached partial Named Result',
    'extra-field union rejected before Run admission and physical work',
  ] : deltaDiffOnly ? [
    'two retained Graph inputs produce one exact independently authored Delta row',
    'node property update and independent parallel-edge removal with unchanged records omitted',
    'unchanged Graphs produce one Delta row with empty typed action arrays',
    'generated Delta Relation Store source revocation verified reload and temporary cleanup',
    'reapplication of the generated Delta matches independent Graph snapshot bytes and CID',
    'sparse rows retain omission explicit NULL and original typed key components through Store reload',
    'ordered Named Result initial read and reattach through public Local and HTTPS',
    'extra-field diff rejected before Run admission and physical work',
  ] : deltaRelationOnly ? [
    'authored Delta update and independent parallel-edge removal precede ordinary Relation consumers',
    'keyed DISTINCT and GROUP coalesce the Required constant key while optional cells remain absent NULL or values',
    'whole-row DISTINCT preserves typed identities and complete sparse rows instead of comparing only that key',
    'Graph and sparse intermediate Relation Store source revocation verified reload and temporary cleanup',
    'Delta removes all nodes and edges while empty GROUP and retained streams keep declaration-derived schema',
    'independent ordered Named Result initial read reattach and declaration-derived aggregate schema',
    'dead-branch Conditional aggregate reference refused before Run admission and physical work',
  ] : selectorDeriveOnly ? [
    'definition and all-candidate label declaration-derived schema and empty/nullability contracts',
    'guaranteed property filter derive projection and independently ordered public read/reattach',
    'sparse intermediate Store save source denial verified reload and temporary body cleanup',
    'unguaranteed derive input rejected before Run admission including empty input',
  ] : deltaApplicationOnly ? [
    'complete Delta records preserve typed identities composite keys and the remaining parallel edge',
    'independent base and target Graph snapshot bytes and CID through save revocation and reload',
    'changed property omission and explicit NULL retained through real Relation Store reload',
    'guaranteed projection initial read reattach and schema through public Local and HTTPS',
    'malformed wrong-base and wrong-target Delta fail with confirmed physical stop and temporary cleanup',
  ] : ['typed MATCH Named Result','independent-key TRAIL identities',
    'inventory-driven unsupported consumer refusal before Run admission and physical work',
    'composite keys and label sets','independent snapshot bytes and CID',
    'physical save, source revocation and verified reload',
    'temporary body reclaimed before restored completion',
    'definition-specific typed key aliases and conditional presence',
    'ordered node_rows and edge_rows on initial read and reattach',
    'Relation Store save, original output unavailable, verified reload with omission and NULL distinct',
    'guaranteed id and labels projection through public Named Results',
    'Required-only filter retains omitted NULL and value cells through Relation Store reload',
    'filter initial read and reattach preserve independent canonical row order and empty schema',
    'Required-key sort and proven-order take retain row presence through Relation Store reload',
    'selection initial read and reattach match independent order without result sorting',
    'conditional property refusal before Run admission',
    'Required-key DISTINCT projects only specified columns and preserves first-occurrence order',
    'keyed DISTINCT Relation Store source denial verified reload and public empty schema',
    'Conditional-key and ordinary Conditional reference refusal before Run admission',
    'whole-row DISTINCT retains typed identity omission and NULL through Relation Store reload',
    'declaration-derived definition selection with empty and nullable Results',
    'selected property filter and alias projection after Relation Store reload',
    'guaranteed selector property filter derive and projection with sparse intermediate Store reload',
    'declaration-derived all-candidate label selection with nullable and empty Results',
    'label selected typed identities raw aliases and Conditional fields survive Relation Store reload',
    'conditional label reference and mixed unknown wrong-kind selector refusal before Run admission',
    'unknown wrong-kind extra-field and selected-column collision refusal before Run admission',
    'path-mode-aware node output with independently ordered minimum eligible depth',
    'node traversal Relation Store retention, source denial and verified reload',
    'complete Delta application with independent Graph and Relation Store reload expectations',
    'Delta followed by sparse keyed and whole-row DISTINCT and GROUP with independent retained streams',
    'Graph diff exact Delta Relation Store reload and reapplication with independent snapshot identities',
    'malformed wrong-base and wrong-target Delta failure with confirmed stop and temporary cleanup'],
};
await writeFile(join(root,'acceptance.json'),JSON.stringify(acceptance,null,2)+'\n');
console.log(output);
// The bounded caller retains stdout after successful installation cleanup.
// Keep source identity and tarball digests there as well as in failed scratch.
console.log(`Packed Property Graph acceptance: ${JSON.stringify(acceptance)}`);
console.log(`Packed Property Graph evidence: ${root}`);
// spawnSync has confirmed every child exited, including both Host processes.
scratch.passed();
