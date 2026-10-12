import {createHash} from 'node:crypto';
import {lstat, readFile} from 'node:fs/promises';
import {gatewayLimits} from './gateway.mjs';

const root = new URL('./dist/', import.meta.url);
const types = Object.freeze({html: 'text/html; charset=utf-8',
  js: 'text/javascript; charset=utf-8', css: 'text/css; charset=utf-8',
  svg: 'image/svg+xml'});
const refused = () => {throw Object.assign(new Error('ExplorerInvalidBuiltAssets'),
  {code: 'ExplorerInvalidBuiltAssets'});};

// Read only the package's frozen build inventory, never a caller's directory.
export async function loadExplorerAssets() {
  if (!(await lstat(root)).isDirectory()) refused();
  const manifestPath = new URL('assets.json', root);
  const manifestStat = await lstat(manifestPath);
  if (!manifestStat.isFile() || manifestStat.size > 16384) refused();
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  if (Object.keys(manifest).sort().join(',') !== 'assets,version' ||
      manifest.version !== 'actql-explorer-assets/0.1' ||
      !Array.isArray(manifest.assets) || manifest.assets.length === 0 ||
      manifest.assets.length > gatewayLimits.assets) refused();
  const assets = new Map(); let size = 0;
  let checkedAssetDirectory = false;
  for (const item of manifest.assets) {
    if (item === null || typeof item !== 'object' ||
        Object.keys(item).sort().join(',') !== 'bytes,path,sha256' ||
        typeof item.path !== 'string' ||
        !/^\/(?:index\.html|assets\/[a-zA-Z0-9_-]+\.(?:js|css|svg))$/u.test(item.path) ||
        assets.has(item.path) || !Number.isSafeInteger(item.bytes) || item.bytes <= 0 ||
        !/^[a-f0-9]{64}$/u.test(item.sha256)) refused();
    size += item.bytes;
    if (size > gatewayLimits.assetBytes) refused();
    if (item.path.startsWith('/assets/') && !checkedAssetDirectory) {
      if (!(await lstat(new URL('assets/', root))).isDirectory()) refused();
      checkedAssetDirectory = true;
    }
    const path = new URL(item.path.slice(1), root);
    const stat = await lstat(path);
    if (!stat.isFile() || stat.size !== item.bytes) refused();
    const body = await readFile(path);
    if (body.length !== item.bytes ||
        createHash('sha256').update(body).digest('hex') !== item.sha256) refused();
    assets.set(item.path, {body, contentType: types[item.path.split('.').at(-1)]});
  }
  if (!assets.has('/index.html')) refused();
  return assets;
}
