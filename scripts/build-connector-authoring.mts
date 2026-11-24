import {chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, renameSync, rmSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {authoringBinPath, authoringToolkitPath} from './connector-authoring-toolkit.mjs';

const cli = 'scripts/connector.mjs';
const referenceDefinition = 'scripts/fixtures/external-rest/connector.json';
const entries = [
  cli,
  'scripts/local-checks-supervisor.mjs',
  'scripts/test-execution.mjs',
  'scripts/test-execution-reporter.mjs',
  'scripts/fixtures/external-rest/normal-case.test.mjs',
  'scripts/fixtures/external-rest/consumer.mjs',
];

export function buildConnectorAuthoring(root: string, packageRoot: string) {
  // Include actual import edges and the child entry points reached by
  // filename. Preserve relative paths so the ordinary runner is also usable
  // from the package without a second set of authoring scripts.
  // The ordinary runner reads supplied framework archives. The lazy checkout
  // inventory used to build those archives remains with the producer.
  const modules = localModuleGraphInputs(root, entries, {external: [
    join(root, 'scripts/connector-host-bundles.mjs'),
    join(root, 'scripts/interface-owner-discovery.mjs'),
    join(root, 'scripts/interface-inventory.mjs'),
  ]});
  const inputs = [...modules, referenceDefinition].sort();
  const destination = join(packageRoot, authoringToolkitPath);
  for (const path of inputs) {
    if (path !== referenceDefinition && !/^scripts\/(?:[\w.-]+\/)*[\w.-]+\.mjs$/u.test(path) &&
        !['adapters/host-common/http-exchange.mjs',
          'adapters/host-common/installed-connector-declaration.mjs'].includes(path)) {
      throw new Error(`UnexpectedConnectorAuthoringInput:${path}`);
    }
    if (!lstatSync(join(root, path)).isFile()) throw new Error(`AliasedConnectorAuthoringInput:${path}`);
  }
  mkdirSync(dirname(destination), {recursive: true});
  if (!lstatSync(dirname(destination)).isDirectory()) {
    throw new Error(`AliasedConnectorAuthoringOutput:${dirname(destination)}`);
  }
  const staged = mkdtempSync(join(dirname(destination), '.connector-authoring-'));
  try {
    for (const path of inputs) {
      const target = join(staged, path);
      mkdirSync(dirname(target), {recursive: true});
      copyFileSync(join(root, path), target);
      chmodSync(target, path === cli ? 0o755 : 0o644);
    }
    if (existsSync(destination) && !lstatSync(destination).isDirectory()) {
      throw new Error(`AliasedConnectorAuthoringOutput:${destination}`);
    }
    rmSync(destination, {recursive: true, force: true});
    renameSync(staged, destination);
    return {bin: join(packageRoot, authoringBinPath), inputs};
  } finally {
    rmSync(staged, {recursive: true, force: true});
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  buildConnectorAuthoring(root, join(root, 'packages/local-node'));
}
