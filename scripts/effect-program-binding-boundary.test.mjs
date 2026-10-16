import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {productionPackageImports} from './source-dependency-closure.mjs';

const manifest = name => readFileSync(new URL(`../src/${name}/moon.pkg`, import.meta.url), 'utf8');

test('static Checker does not depend on the concrete Effect binding layer', () => {
  const imports = productionPackageImports(manifest('program_check'));
  for (const downstream of ['effect_program_binding', 'run_publication', 'effect_application', 'physical_strategy', 'run_publication_host']) {
    assert.ok(!imports.includes(downstream), downstream);
  }
  // The public test package may exercise downstream consumers without adding a
  // production dependency back into the Checker.
  const bindingImports = productionPackageImports(manifest('effect_program_binding'));
  for (const dependency of ['program_check', 'run_publication', 'effect_application']) {
    assert.ok(bindingImports.includes(dependency), dependency);
  }
  assert.ok(!bindingImports.some(name => /^(platform_native|connectors|physical_host|run_publication_host)(\/|$)/u.test(name)));
});

test('concrete Effect handles stay abstract and are absent from the Checker API', () => {
  const checker = readFileSync(new URL('../src/program_check/pkg.generated.mbti', import.meta.url), 'utf8');
  const binding = readFileSync(new URL('../src/effect_program_binding/pkg.generated.mbti', import.meta.url), 'utf8');
  for (const name of ['EffectProgramStaticPreview', 'EffectProgramRunCandidate', 'EffectProgramRunPreview']) {
    assert.doesNotMatch(checker, new RegExp(`\\b${name}\\b`, 'u'));
    assert.match(binding, new RegExp(`^type ${name}$`, 'mu'));
    assert.doesNotMatch(binding, new RegExp(`^(?:pub\\(all\\) )?(?:struct|enum) ${name}\\b`, 'mu'));
  }
  for (const name of ['EffectComputationCandidate', 'EffectProgramStaticCandidate']) {
    assert.match(checker, new RegExp(`^type ${name}$`, 'mu'));
  }
});
