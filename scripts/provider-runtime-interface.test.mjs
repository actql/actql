import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import {javascriptInterface} from './interface-inventory.mjs';

function projection(source) {
  const references = [];
  const syntax = javascriptInterface(source, {resolveRuntimeImport(reference) {
    references.push(reference);
    return ['./original-runtime.mjs'];
  }});
  return {references, syntax};
}

test('runtime Owner projection retains actual closed arguments and base', () => {
  const {references} = projection(`import {providerBundleUrl} from './owner.mjs';
    const bundle = providerBundleUrl({providerBundle: 'unregistered'}, 'file:///foreign/owner.mjs');
    export const load = () => import(bundle.href);`);
  assert.deepEqual(references, [{kind: 'owner-projection', source: './owner.mjs', name: 'providerBundleUrl',
    arguments: [{kind: 'object', properties: {providerBundle: {kind: 'value', value: 'unregistered'}}},
      {kind: 'value', value: 'file:///foreign/owner.mjs'}]}]);
});

test('runtime Owner projection follows private selected-entry flow without replacing its original selectors', () => {
  for (const module of ['installed-source', 'installed-effect']) {
    const source = readFileSync(`adapters/host-node/${module}.mjs`, 'utf8');
    const {references} = projection(source);
    const original = references.find(value => value.kind === 'owner-projection');
    assert(original, module);
    assert.equal(original.arguments.length, 1);
    const body = JSON.stringify(original.arguments[0]);
    assert.match(body, /installedConnectorFor"/u);
    assert.match(body, /installedConnectorForTable"/u);
    assert.match(body, /installedConnectors/u);
  }
});

test('runtime Owner projection refuses changed import bindings and unknown entry flow', () => {
  for (const replacement of ['providerBundleUrl = replacement;', '({project: providerBundleUrl} = replacement);']) {
    const {references, syntax} = projection(`import {providerBundleUrl} from './owner.mjs';
      ${replacement} const bundle = providerBundleUrl({providerBundle: 'known'});
      export const load = () => import(bundle.href);`);
    assert.equal(references.length, 0);
    assert.equal(syntax.unresolvedSyntax.length, 1);
  }
  const {references} = projection(`import {providerBundleUrl} from './owner.mjs';
    function load(entry) { entry.providerBundle = 'substituted';
      const bundle = providerBundleUrl(entry); return import(bundle.href); }
    export {load};`);
  assert.equal(references[0].arguments[0].kind, 'unresolved');
});

test('runtime Owner projection does not equate safe extraction with an escaping private callback', () => {
  const source = `import {providerBundleUrl, installedConnectorFor} from './owner.mjs';
    function load(entry) { const bundle = providerBundleUrl(entry); return import(bundle.href); }
    const entry = installedConnectorFor(table, profile); load(entry); acceptForeignCallback(load);`;
  assert.equal(projection(source).references[0].arguments[0].kind, 'runtime-parameter');
});
