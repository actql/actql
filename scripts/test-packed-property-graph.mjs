// Consume fresh public tarballs without a checkout or MoonBit lookup path.
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';
import {CLIENT_PACKAGES, checkoutState, packedClientPackage, packedNpmCache} from './packed-client-packages.mjs';
import {certificates} from '../adapters/site-node/https-agent-harness.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const selectorDeriveOnly = process.argv.includes('--selector-derive-only');
const deltaApplicationOnly = process.argv.includes('--delta-application-only');
if (process.argv.slice(2).some(argument=>!['--selector-derive-only',
  '--delta-application-only'].includes(argument)) ||
  (selectorDeriveOnly && deltaApplicationOnly)) {
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
async function run(command, args, cwd = root, env = environment) {
  const result = spawnSync(command,args,{cwd,env,encoding:'utf8',timeout:600_000});
  await writeFile(join(root,`${++sequence}.log`),`${result.stdout ?? ''}\n${result.stderr ?? ''}`);
  if (result.error || result.status !== 0) throw new Error(
    `${command} ${args.join(' ')} failed (status ${result.status}); evidence: ${root}`,
    {cause:result.error});
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
  'fixtures/property-graph-definition-rows.program.json',
  'fixtures/property-graph-label-rows.program.json',
  'fixtures/property-graph-selector-derive.program.json',
  'fixtures/property-graph-traverse-nodes.expected.json']) await copyFile(join(repository,'scripts',name),join(root,name));
await copyFile(join(repository,'docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json'),
  join(root,'local-family-coverage.json'));
await mkdir(join(root,'tls'));
await certificates(join(root,'tls'));
const output = await run(process.execPath,['--test',
  ...(selectorDeriveOnly ? ['--test-name-pattern','selector property derive'] : []),
  ...(deltaApplicationOnly ? ['--test-name-pattern','complete Delta application'] : []),
  'property-graph-public-host.test.mjs'],root,
  {...environment,ACTQL_PROPERTY_GRAPH_PACKED:'1',
    PATH:[dirname(process.execPath),'/usr/bin','/bin'].join(':')});
const digests = {};
for (const name of CLIENT_PACKAGES) {
  const file = `actql-${name}-0.0.0-development.tgz`;
  digests[file] = 'sha256:' + createHash('sha256').update(await readFile(join(root,file))).digest('hex');
}
const acceptance = {
  version:'property-graph-packed-acceptance/0.1',node:process.version,
  source,
  packages:digests,paths:['embedded-local','remote-https'],
  selection:selectorDeriveOnly ? 'selector-derive' : deltaApplicationOnly ? 'delta-application' : 'all',
  independentFixture:'fixtures/property-graph-parallel.program.json',
  presenceFixture:'fixtures/property-graph-presence.program.json',
  definitionFixture:'fixtures/property-graph-definition-rows.program.json',
  labelFixture:'fixtures/property-graph-label-rows.program.json',
  selectorDeriveFixture:'fixtures/property-graph-selector-derive.program.json',
  traversalFixture:'fixtures/property-graph-traverse-nodes.expected.json',
  assertions:selectorDeriveOnly ? [
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
