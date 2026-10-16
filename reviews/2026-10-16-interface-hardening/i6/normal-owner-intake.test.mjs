import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
import {interfaceGenerationFreshness} from '../../../scripts/interface-generation-freshness.mjs';
import {interfaceOwnerDeclarations} from '../../../scripts/interface-owner-discovery.mjs';
import {interfaceOwnerCoverage} from '../../../scripts/interface-owner-coverage.mjs';
import {sourceInterfaceClosure} from '../../../scripts/source-interface-closure.mjs';
import {pythonInterfaceSources} from '../../../scripts/python-interface-sources.mjs';

test('normal owner intake verifies generation and reports every uncovered authored module explicitly', async () => {
  const directory = '/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/';
  const vite = JSON.parse(readFileSync(directory + 'i6-actual-vite-source-coverage-550f4cb7482b.json', 'utf8'));
  assert.equal(vite.readerSource, '550f4cb7482ba7b718c9d906cfb93ecc3dbcefc3');
  // Reuse the verified input metadata only while every authored input remains
  // byte-identical. This does not relabel its original build or artifact source.
  for (const item of [...vite.modules, ...vite.assets]) assert.equal(
    createHash('sha256').update(readFileSync(item.module)).digest('hex'), item.sha256,
    `Changed configured Vite input: ${item.module}`);
  const source = await sourceInterfaceClosure(process.cwd(), {generatedInputs: vite.sourceArtifacts});
  const python = pythonInterfaceSources(process.cwd());
  // The retained older reader included manually loaded config files alongside
  // actual bundled source. Keep their hashes as build provenance, not invented
  // distributed operations. A config actually bundled by Vite stays authored.
  const bundled = new Set(vite.generated.flatMap(value => value.sourceModules ?? []));
  const configurationOnly = new Set(vite.sourceArtifacts.map(value => value.build)
    .filter(value => !bundled.has(value)));
  const configuredModules = vite.modules.filter(value => !configurationOnly.has(value.module));
  const configurationInputs = vite.modules.filter(value => configurationOnly.has(value.module));
  const actual = new Map();
  for (const module of [...source.modules, ...source.types, ...configuredModules, ...python.modules]) {
    const previous = actual.get(module.module);
    if (previous) assert.deepEqual(previous, module, `Conflicting syntax projection: ${module.module}`);
    actual.set(module.module, module);
  }
  const freshness = interfaceGenerationFreshness(process.cwd());
  const owners = interfaceOwnerDeclarations(process.cwd());
  const result = interfaceOwnerCoverage({root: process.cwd(), modules: [...actual.values()], owners,
    generated: freshness.generated, requireComplete: false});
  assert(result.covered >= 70);
  assert.equal(result.complete, false, 'this intermediate intake must not claim all-I6 completion');
  assert.throws(() => interfaceOwnerCoverage({root: process.cwd(), modules: [...actual.values()], owners,
    generated: freshness.generated}), /Unregistered distributed interfaces/u);
  const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  const report = {...result, readerSource, freshness: freshness.qualification,
    normalRoots: source.roots, pythonCandidates: python.roots,
    missingInterfaces: result.missing.map(name => actual.get(name)),
    compiledMoonProvenanceModules: source.moon.modules.length,
    configurationInputs: configurationInputs.map(({module, sha256}) => ({module, sha256})),
    configuredViteSource: vite.readerSource, cloud: 'separate actual root projection, not yet composed'};
  writeFileSync(directory + `i6-normal-owner-intake-${readerSource.slice(0, 12)}.json`, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({modules: result.modules, covered: result.covered, missing: result.missing.length,
    owners: owners.length, generationChecks: freshness.checked.length, complete: result.complete}));
});
