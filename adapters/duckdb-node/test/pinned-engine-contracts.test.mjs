import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {pinnedEngineContracts, pinnedEngineFixture} from
  './pinned-engine-contracts.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));

test('pinned contracts are selected by name and validated against their pins',
  async () => {
    const contracts = await pinnedEngineContracts(root, [
      'registered_fragment',
      'registered_body',
      'registered_values',
      'registered_ordered',
    ]);
    assert.deepEqual(contracts.map(value => JSON.parse(value).operation), [
      'ACTQL.expression_fragment/0.1',
      undefined,
      'REL.values',
      'REL.derive',
    ]);
  });

test('an unrelated generated fixture cannot shift a named contract',
  async () => {
    const source = await readFile(join(root,
      'src/query_integration/pinned_engine_contracts_wbtest.mbt'), 'utf8');
    const injected = source.replace(
      '\n///|\nfn registered_values()',
      '\n///|\nfn unrelated_fixture() -> Unit { () }' +
        '\n\n///|\nfn registered_values()',
    );
    assert.equal(
      pinnedEngineFixture(injected, 'registered_fragment'),
      pinnedEngineFixture(source, 'registered_fragment'),
    );
    assert.throws(
      () => pinnedEngineFixture(injected, 'unrelated_fixture'),
      {code: 'UnknownPinnedEngineFixture'},
    );
    assert.throws(
      () => pinnedEngineFixture(injected, 'missing_fixture'),
      {code: 'UnknownPinnedEngineFixture'},
    );
    const missing = source.replace('fn registered_fragment()',
      'fn removed_fragment()');
    assert.throws(
      () => pinnedEngineFixture(missing, 'registered_fragment'),
      {code: 'MissingPinnedEngineFixture'},
    );
  });
