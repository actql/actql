import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {test} from 'node:test';
import {assertInterfaceCoverage} from '../../../scripts/interface-inventory.mjs';
import {projectOwnerSources} from '../../../scripts/interface-owner-source-projection.mjs';

const directory = '/Users/t14i/workspace/20260822/reviews/2026-10-16-interface-hardening/';
function read(name, expected) {
  const bytes = readFileSync(directory + name);
  if (expected) assert.equal(createHash('sha256').update(bytes).digest('hex'), expected);
  return JSON.parse(bytes);
}
function check(metadata, modules, count) {
  const readReference = path => execFileSync('git', ['show', `${metadata.source}:${path}`],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  assert.equal(assertInterfaceCoverage({root: process.cwd(), modules,
    declarations: metadata.declarations, generated: metadata.generated ?? [], readReference}), count);
}

test('A final actual-layout names and original operation references cover the merged syntax', () => {
  const metadata = read('a-js-binding-interface-declarations-final.json',
    '644be429cce92f9168a6fb7deda8c8baad68a9c1c6ce755a6c8a8229244987e8');
  const original = read('a-09e3-owner-source-projection.json', metadata.syntaxProjectionSha256);
  const final = read('a-f2df-owner-source-projection.json', metadata.finalEightSyntaxProjection.sha256);
  const modules = new Map(original.modules.map(value => [value.module, value]));
  final.modules.forEach(value => modules.set(value.module, value));
  check(metadata, [...modules.values()], 53);
});

test('F original Provider operation references cover the separately qualified syntax', () => {
  const metadata = read('f-provider-owner-declarations.json',
    'f9f1a2b8ce793caba4f5f1fff561f2ce9095afa5560cf969cc8e15fd4db3d8b8');
  check(metadata, read('f-owner-source-projection.json',
    'd0d49876bdef6b7090fdd4b3f53b8ffaf8e1eebadd5d932c61825ddfb63e8a2b').modules, 12);
});

test('F narrowed functional references cover original syntax without approving its old raw tuple access', () => {
  const metadata = read('f-a15-owner-declarations-v2.json',
    'ada37990d778d34ce202ec3d3266863871a4f56c67ce9a0ba549cfbae3e95e6d');
  const modules = read('f-a15-owner-source-projection.json',
    '98fee2bcc88e0ddf73a3100fbba52e9d9a7a370776d18fbe287c37f799920f8b').modules;
  // Validate functional declarations independently of the separately failing
  // representation policy. This is not admission of the old implementation.
  check(metadata, modules.map(value => ({...value, compilerFields: []})), 16);
  assert.throws(() => check(metadata, modules, 16), /Compiler representation outside generated binding/u);
});

test('E fixed generated wire JS and Python use the same immutable syntax readers', () => {
  const source = 'd0ccdb95691eb9ee41dea4d1982df84ca98dff70';
  const result = projectOwnerSources(process.cwd(), {source,
    base: '02f9e53f29b4913d5c6e8276d2ac248800fe8173', all: true, paths: [
      'packages/client-wire/client-host.generated.js', 'packages/client-wire/publication.generated.js',
      'packages/client-wire/interactive-control.generated.js',
      'packages/python-sdk/src/actql_sdk/_wire.py', 'packages/python-sdk/src/actql_sdk/_wire_codec.py']});
  assert.equal(result.modules.length, 5);
  assert.equal(result.modules.filter(value => value.module.endsWith('.py')).length, 2);
  assert(result.modules.every(value => value.exports.length && value.operations.length));
  const readerSource = execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim();
  const bytes = JSON.stringify({...result, readerSource}, null, 2) + '\n';
  writeFileSync(directory + 'e-d0cc-owner-source-projection.json', bytes);
  console.log(JSON.stringify({owner: 'E', modules: 5,
    operations: result.modules.reduce((sum, value) => sum + value.operations.length, 0),
    sha256: createHash('sha256').update(bytes).digest('hex')}));
});
