import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, open} from 'node:fs/promises';
import {gatewayLimits} from './gateway.mjs';

const root = new URL('./dist/', import.meta.url);
const types = Object.freeze({html: 'text/html; charset=utf-8',
  js: 'text/javascript; charset=utf-8', css: 'text/css; charset=utf-8',
  svg: 'image/svg+xml'});
const refused = () => {throw Object.assign(new Error('ExplorerInvalidBuiltAssets'),
  {code: 'ExplorerInvalidBuiltAssets'});};
async function boundedFile(path, limit, exactBytes) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size > limit ||
        exactBytes !== undefined && stat.size !== exactBytes) refused();
    const buffer = Buffer.alloc(limit + 1); let length = 0;
    while (length < buffer.length) {
      const {bytesRead} = await file.read(buffer, length, buffer.length - length, null);
      if (bytesRead === 0) break;
      length += bytesRead;
    }
    if (length > limit || exactBytes !== undefined && length !== exactBytes) refused();
    return buffer.subarray(0, length);
  } finally {await file.close();}
}

// Read only the package's frozen build inventory, never a caller's directory.
export async function loadExplorerAssets() {
  if (!(await lstat(new URL('./dist', import.meta.url))).isDirectory()) refused();
  const manifestPath = new URL('assets.json', root);
  const manifestStat = await lstat(manifestPath);
  if (!manifestStat.isFile() || manifestStat.size > 16384) refused();
  const manifest = JSON.parse((await boundedFile(manifestPath, 16384)).toString('utf8'));
  if (manifest === null || typeof manifest !== 'object' || Array.isArray(manifest) ||
      Object.keys(manifest).sort().join(',') !== 'assets,version' ||
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
        typeof item.sha256 !== 'string' || !/^[a-f0-9]{64}$/u.test(item.sha256)) refused();
    size += item.bytes;
    if (size > gatewayLimits.assetBytes) refused();
    if (item.path.startsWith('/assets/') && !checkedAssetDirectory) {
      if (!(await lstat(new URL('assets', root))).isDirectory()) refused();
      checkedAssetDirectory = true;
    }
    const path = new URL(item.path.slice(1), root);
    const stat = await lstat(path);
    if (!stat.isFile() || stat.size !== item.bytes) refused();
    const body = await boundedFile(path, item.bytes, item.bytes);
    if (body.length !== item.bytes ||
        createHash('sha256').update(body).digest('hex') !== item.sha256) refused();
    assets.set(item.path, {body, contentType: types[item.path.split('.').at(-1)]});
  }
  if (!assets.has('/index.html')) refused();
  return assets;
}
