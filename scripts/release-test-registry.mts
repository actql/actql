// Read-only private registry for fixed-artifact npm dependency resolution.
// It is acceptance infrastructure, never a public publication substitute.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';

export async function openReleaseTestRegistry(cohorts) {
  const artifacts = [];
  for (const {directory, manifest} of cohorts) {
    for (const item of manifest.packages) {
      assert(!artifacts.some(v => v.item.name === item.name), 'Duplicate registry package');
      artifacts.push({item, metadata: JSON.parse(execFileSync('tar', ['-xOf', join(directory, item.file),
        'package/package.json'], {encoding: 'utf8'})), bytes: await readFile(join(directory, item.file))});
    }
  }
  const requested = [];
  const server = createServer((request, response) => {
    try {
      assert.equal(request.method, 'GET');
      const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).slice(1); requested.push(path);
      const archive = artifacts.find(v => path === `archives/${v.item.file}`);
      if (archive) {response.writeHead(200, {'content-type': 'application/octet-stream'}); response.end(archive.bytes); return;}
      const artifact = artifacts.find(v => path === v.item.name || path === `${v.item.name}/${v.item.version}`);
      if (!artifact) {response.writeHead(404); response.end('{}'); return;}
      const metadata = {...artifact.metadata, dist: {integrity: artifact.item.integrity, tarball: `${url}archives/${artifact.item.file}`}};
      response.writeHead(200, {'content-type': 'application/json'});
      response.end(JSON.stringify(path === artifact.item.name ? {name: artifact.item.name, 'dist-tags': {latest: artifact.item.version},
        versions: {[artifact.item.version]: metadata}} : metadata));
    } catch {response.writeHead(400); response.end('{}');}
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  const url = `http://127.0.0.1:${server.address().port}/`;
  return {url, requested, close: () => new Promise((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve());
  })};
}
