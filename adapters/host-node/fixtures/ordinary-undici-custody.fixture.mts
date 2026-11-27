import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdirSync, readdirSync, readFileSync, symlinkSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join} from 'node:path';

type ImageFact = Readonly<{path: string; bytes: number; sha256: string}>;
type Dependency = Readonly<{name: string; package?: number; local?: boolean}>;
type TransportInventory = {
  images: ImageFact[];
  packages: {name: string; version: string; images: ImageFact[]; dependencies: Dependency[]}[];
  dependencies: Dependency[];
};
const fact = (path: string, bytes: Uint8Array): ImageFact => ({path, bytes: bytes.length,
  sha256: createHash('sha256').update(bytes).digest('hex')});

export function admitFixtureUndici({directory, root}: Readonly<{directory: string; root: string}>) {
  const packagePath = createRequire(import.meta.url).resolve('undici/package.json');
  const original = dirname(packagePath), packageBytes = readFileSync(packagePath);
  const {version} = JSON.parse(packageBytes.toString('utf8')) as {version: string};
  assert.equal(version, '7.30.0');
  const localManifestPath = join(root, 'package.json');
  const manifest = JSON.parse(readFileSync(localManifestPath, 'utf8'));
  manifest.dependencies = {undici: version};
  const transportPath = 'adapters/host-node/original-model-http-transport.mjs';
  manifest.exports = {'.': './index.mjs', './_internal/model-http-transport': './' + transportPath};
  const localBytes = Buffer.from(JSON.stringify(manifest));
  writeFileSync(localManifestPath, localBytes);
  mkdirSync(join(directory, 'node_modules'), {recursive: true});
  symlinkSync(original, join(directory, 'node_modules/undici'));
  mkdirSync(join(directory, 'node_modules/@actql'), {recursive: true});
  symlinkSync(root, join(directory, 'node_modules/@actql/local-node'));
  const transportImages = [transportPath, 'adapters/host-common/model-response-reader.mjs',
    ...['normal-http-chat','installed-http-chat','model-port','original-chat-request','original-materials',
      'bounded-response','compiler-binding.generated'].map(name => 'adapters/host-node/model-http/' + name + '.mjs'),
  ].map(path => {
    const prefix = 'adapters/host-node/model-http/';
    const relative = path.startsWith(prefix) ? 'packages/provider-http/_internal/' + path.slice(prefix.length) : path;
    const source = readFileSync(new URL('../../../' + relative, import.meta.url));
    mkdirSync(dirname(join(root, path)), {recursive: true});
    writeFileSync(join(root, path), source);
    return fact(path, source);
  });
  const images = readdirSync(original, {recursive: true, withFileTypes: true})
    .filter(entry => entry.isFile() && /\.(?:[cm]?js|json|wasm)$/u.test(entry.name))
    .map(entry => {
      const path = join(entry.parentPath, entry.name);
      return fact(path.slice(original.length + 1), readFileSync(path));
    });
  function include(data: TransportInventory) {
    data.images = data.images.map(image => image.path === 'package.json' ? fact('package.json', localBytes) : image);
    data.images.push(...transportImages);
    const index = data.packages.push({name: 'undici', version, images: [...images], dependencies: []}) - 1;
    data.dependencies.push({name: 'undici', package: index});
    return index;
  }
  return {original, version, include};
}
