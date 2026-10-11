import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {publicationRegistry} from './run-publication-registry.mjs';

const registryPath = 'spec/contracts/actql-run-publication.json';
const manifestPath = 'spec/spec-family.json';
const documentPath = 'docs/spec/protocols/artifacts.md';
const names = ['model_raw_capture_policy', 'model_raw_response'];
export function checkModelRawCaptureContract(write = false) {
  const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  assert.deepEqual(registry, publicationRegistry());
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const owner = manifest.documents.find(d => d.path === documentPath);
  assert.ok(owner);
  let source = readFileSync(documentPath, 'utf8');
  const pins = names.map(name => ({path: registryPath, pointer: `/schemas/${name}`,
    cid: machineCid(registry.schemas[name]), version: registry.version}));
  for (const pointer of ['/reference_roles', '/reference_graph']) {
    pins.push({path: registryPath, pointer,
      cid: machineCid(registry[pointer.slice(1)]), version: registry.version});
  }
  for (const pin of pins) {
    const old = owner.machine_contracts.find(p =>
      p.path === pin.path && p.pointer === pin.pointer);
    if (write) {
      const prefix = `../../../${pin.path}#${pin.pointer} `;
      const line = source.split('\n').find(value => value.startsWith(prefix));
      if (line) source = source.replace(line, prefix + pin.cid);
      if (old) {
        Object.assign(old, pin);
      } else owner.machine_contracts.push(pin);
    } else assert.deepEqual(old, pin);
  }
  const section = '<!-- model-raw-capture-pins:start -->\n```text\n' +
    pins.slice(0, 2).map(p => `../../../${p.path}#${p.pointer} ${p.cid}`).join('\n') +
    '\n```\n<!-- model-raw-capture-pins:end -->';
  const pattern = /<!-- model-raw-capture-pins:start -->[\s\S]*?<!-- model-raw-capture-pins:end -->/u;
  assert.ok(pattern.test(source));
  if (write) {
    source = source.replace(pattern, section);
    writeFileSync(documentPath, source);
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  } else assert.equal(source.match(pattern)[0], section);
  for (const p of pins) assert.ok(source.includes(
    `../../../${p.path}#${p.pointer} ${p.cid}`));
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  checkModelRawCaptureContract(process.argv.includes('--write'));
  console.log('Private Model raw policy/envelope pins verified.');
}
