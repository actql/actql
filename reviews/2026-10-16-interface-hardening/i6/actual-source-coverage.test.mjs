import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {sourceInterfaceClosure} from '../../../scripts/source-interface-closure.mjs';

test('actual ordinary package source intake reports unresolved generated entrances explicitly', async () => {
  const result = await sourceInterfaceClosure(process.cwd(), {reportUnresolvedEntrances: true});
  assert(result.roots.some(value => value.kind === 'npm-cli'));
  assert(result.roots.some(value => value.name === '@actql/provider-http'));
  assert(result.modules.length && result.moon.modules.length);
  const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  const report = {...result, readerSource,
    modules: result.modules.map(({module, sha256, exports, operations, compilerFields, unresolvedSyntax}) =>
      ({module, sha256, exports: exports.length, operations: operations.length, compilerFields, unresolvedSyntax})),
    types: {modules: result.types.length}, moon: {packages: result.moon.packages, modules: result.moon.modules.length}};
  writeFileSync('/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/i6-actual-source-coverage.json',
    JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({qualification: result.qualification, roots: result.roots.length,
    modules: result.modules.length, types: result.types.length, moonModules: result.moon.modules.length,
    unresolvedEntrances: result.unresolvedEntrances,
    compilerFields: result.modules.filter(value => value.compilerFields?.length)
      .map(({module, compilerFields}) => ({module, compilerFields}))}));
});
