// Follow authored fixture imports while keeping the real installed product
// graph external. Product source is never copied as a fixture fallback.
import {dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {realpathSync} from 'node:fs';
import {copyFile, mkdir} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {localModuleGraphInputs} from './adapter-module-graph.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';

export function packedFixtureSupport(root, entries,
  {productEntries = localNodePackageInputs(root).adapterEntries} = {}) {
  root = realpathSync(root);
  const product = localModuleGraphInputs(root, productEntries);
  const modules = localModuleGraphInputs(root, entries.filter(path => path.endsWith('.mjs')), {
    external: [...product.map(path => resolve(root, path)),
      join(root, 'packages/*'), join(root, '_build/*')],
  });
  const support = [...new Set([...entries, ...modules])].sort();
  for (const path of support) {
    const suffix = relative(root, resolve(root, path));
    if (isAbsolute(suffix) || suffix === '..' || suffix.startsWith('..' + sep)) {
      throw new Error(`Unpackaged fixture import: ${path}`);
    }
  }
  return support;
}

export async function stageShortQueryFixtures({repository, destination}) {
  const entry = 'scripts/fixtures/packed-short-queries.mjs';
  const files = [];
  for (const path of packedFixtureSupport(repository, [entry])) {
    const suffix = relative('scripts/fixtures', path);
    if (isAbsolute(suffix) || suffix === '..' || suffix.startsWith('..' + sep)) {
      throw new Error(`Unpackaged short-query fixture: ${path}`);
    }
    const name = path === entry ? 'short-queries.mjs' : suffix;
    const target = join(destination, name);
    await mkdir(dirname(target), {recursive: true});
    await copyFile(join(repository, path), target);
    files.push(name);
  }
  return files;
}

export const packedReadOpeningFixtureInputs = Object.freeze([
  'adapters/host-node/client-read-opening.test.mjs',
  'adapters/host-node/client-read-opening.fixture.mjs',
  'adapters/host-node/funded-client-preparation.fixture.mjs',
  'adapters/host-node/client-read-opening-restart.fixture.mjs',
  'adapters/host-node/client-read-run-capacity.test.mjs',
  'adapters/host-node/client-read-run-capacity.fixture.mjs',
  'adapters/host-node/fixtures/read-121.program.json',
  'adapters/host-node/fixtures/read-121.expected.json',
  'adapters/host-node/client-values-row-limit.test.mjs',
  'adapters/host-node/client-values-row-limit.fixture.mjs',
  'adapters/host-node/client-cancellation-public.test.mjs',
  'adapters/host-node/client-cancellation-attempt-installed.test.mjs',
  'adapters/host-node/client-cancellation-public.fixture.mjs',
  'adapters/host-node/client-submission-custody-public.test.mjs',
  'adapters/host-node/client-submission-custody-public.fixture.mjs',
  'adapters/host-node/submission-epoch-public.test.mjs',
  'adapters/host-node/client-effect-uncertainty.test.mjs',
  'adapters/host-node/client-owner-observations-public.test.mjs',
  'adapters/host-node/client-effect-cancellation-public.test.mjs',
  'adapters/connectors/salesforce/test/read-compute-effect.fixture.mjs',
  'adapters/connectors/salesforce/test/read-compute-effect.embedded-child.mjs',
  'adapters/connectors/salesforce/test/salesforce-effect-site.fixture.mjs',
  'scripts/fixtures/client-effect-uncertainty.child.mjs',
  'scripts/fixtures/client-effect-cancellation.child.mjs',
  'adapters/site-node/https-exchange-fixture.mjs',
  'scripts/owned-scratch.mjs',
  'packages/sdk/fixtures/values.json',
  'packages/sdk/fixtures/values.environment.json',
]);

// The isolated copy and its tests use the same installed import decisions.
export function rewritePackedFixtureSource(text, {repository, path, support, installedHost}) {
  if (path.endsWith('.mjs') && path !== 'scripts/owned-scratch.mjs') {
    text = text.replace(
      "import {openInstalledRemoteHttpHost, publishInstalledEffect} from\n  '../../../host-node/embedded-local.mjs';",
      "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';\n" +
      "import {publishEffect as publishInstalledEffect} from '@actql/local-node';");
    text = text.replace(/import \{connectEmbeddedLocal\} from ['"](?:\.\.\/)+(?:adapters\/)?host-node\/embedded-local\.mjs['"];/gu,
      "import {connect as connectEmbeddedLocal} from '@actql/local-node';");
    if (path === 'scripts/fixtures/client-effect-cancellation.child.mjs') {
      text = text.replace(
        "import {openInstalledRemoteHttpHost} from '../../adapters/host-node/embedded-local.mjs';",
        "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';");
    }
    if (path === 'adapters/host-node/client-owner-observations-public.test.mjs' ||
        path === 'adapters/host-node/client-values-row-limit.test.mjs' ||
        path === 'adapters/host-node/client-values-row-limit.fixture.mjs' ||
        path === 'adapters/host-node/client-cancellation-public.fixture.mjs' ||
        path === 'adapters/host-node/submission-epoch-public.test.mjs') {
      text = text.replace(
        "import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';",
        "import {connect as connectEmbeddedLocal} from '@actql/local-node';\n" +
        "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';");
      text = text.replace(
        "import {connectEmbeddedLocal,openInstalledRemoteHttpHost} from './embedded-local.mjs';",
        "import {connect as connectEmbeddedLocal} from '@actql/local-node';\n" +
        "import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';");
    }
    text = text.replace(/from\s+(['"])([^'"]+)\1/gu, (original, quote, specifier) => {
      if (specifier.startsWith('node:') || specifier.startsWith('@actql/')) return original;
      const target = relative(repository, resolve(repository, path, '..', specifier));
      if (support.includes(target)) return original;
      if (target === 'packages/node/index.mjs') return `from ${quote}@actql/node${quote}`;
      if (target === 'packages/local-node/http-host.mjs') return `from ${quote}@actql/local-node/http-host${quote}`;
      if (target === 'packages/client-wire/index.mjs') return `from ${quote}@actql/client-wire${quote}`;
      if (target === 'packages/sdk/index.mjs') return `from ${quote}@actql/sdk${quote}`;
      if (target === 'packages/sdk/host-port.mjs') return `from ${quote}@actql/sdk/host-port${quote}`;
      if (target === 'packages/sdk/internal/private-source-preparation.mjs') {
        return `from ${quote}@actql/sdk/_internal/source-preparation${quote}`;
      }
      if (target === '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js') {
        return `from ${quote}@actql/local-node/runtime${quote}`;
      }
      if (target === '_build/js/release/build/connectors/salesforce/host_node/host_node.js') {
        return `from ${quote}${pathToFileURL(join(installedHost, target)).href}${quote}`;
      }
      if (!target.startsWith('adapters/')) throw new Error(`Unpackaged fixture import: ${target}`);
      return `from ${quote}${pathToFileURL(join(installedHost, target)).href}${quote}`;
    }).replace(/new URL\('((?:\.\.\/)+spec\/[^']+)', import.meta.url\)/gu,
      (_original, specifier) => `new URL(${JSON.stringify(pathToFileURL(join(installedHost,
        relative(repository, resolve(repository, path, '..', specifier)))).href)})`);
    text = text.replace(/new URL\(\s*'\.\.\/\.\.\/\.\.\/\.\.\/_build\/js\/release\/build\/connectors_builtin_node\/' \+\s*'connectors_builtin_node\.js', import\.meta\.url\)/gu,
      `new URL(${JSON.stringify(pathToFileURL(join(installedHost,
        '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')).href)})`);
  }
  return text;
}
