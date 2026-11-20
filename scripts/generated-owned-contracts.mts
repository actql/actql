// Compilers rename variables and duplicate admitted source across bundles.
// Generated text is therefore checked against admitted production tokens;
// the original source still requires its exact reviewed context and count.
import {violations} from './check-owned-contract-versions.mjs';

const production = (path: string) => path.startsWith('src/') && path.endsWith('.mbt') &&
  !/(?:^|\/)[^/]*(?:_test|_wbtest)\.mbt$/u.test(path);

export function assertGeneratedOwnedContracts({source, generated, inventory}: {source: Parameters<typeof violations>[0]; generated: Parameters<typeof violations>[0]; inventory: Parameters<typeof violations>[1]}) {
  const rejectedSource = violations(source, inventory);
  if (rejectedSource.length) {
    throw new Error('Unadmitted owned source contract contexts:\n' +
      rejectedSource.map(item => `${item.path}:${item.line}: ${item.token}`).join('\n'));
  }
  const admitted = new Set(source.filter(item => production(item.path))
    .map(item => item.token));
  const rejectedGenerated = generated.filter(item => !admitted.has(item.token));
  if (rejectedGenerated.length) {
    throw new Error('Generated owned contracts require admitted production source:\n' +
      rejectedGenerated.map(item => `${item.path}:${item.line}: ${item.token}`).join('\n'));
  }
}
