import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {isDeepStrictEqual} from 'node:util';

const names = Object.freeze({
  registered_body: Object.freeze({version: undefined, operation: undefined}),
  registered_values: Object.freeze({
    version: 'actql-rel-values-execution/0.1',
    operation: 'REL.values',
  }),
  registered_ordered: Object.freeze({
    version: 'actql-ordered-derive-execution/0.1',
    operation: 'REL.derive',
  }),
  registered_fragment: Object.freeze({
    version: 'actql-expression-fragment-execution/0.1',
    operation: 'ACTQL.expression_fragment/0.1',
  }),
});

const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);

const cid = value => `sha256:${createHash('sha256')
  .update(canonical(value)).digest('hex')}`;

const fail = (code, fixture, cause) => {
  const error = Object.assign(new Error(`${code}: ${fixture}`), {
    code,
    fixture,
  });
  if (cause !== undefined) error.cause = cause;
  throw error;
};

function namedFixture(source, name) {
  if (!Object.hasOwn(names, name)) fail('UnknownPinnedEngineFixture', name);
  const marker = `fn ${name}()`;
  const start = source.indexOf(marker);
  if (start === -1) fail('MissingPinnedEngineFixture', name);
  const next = source.indexOf('\n///|', start + marker.length);
  const body = source.slice(start, next === -1 ? source.length : next);
  const match = body.match(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")/);
  if (!match) fail('MissingPinnedEngineFixtureJSON', name);
  try {
    const encoded = JSON.parse(match[1]);
    return Object.freeze({encoded, value: JSON.parse(encoded)});
  } catch (cause) {
    fail('InvalidPinnedEngineFixtureJSON', name, cause);
  }
}

export const pinnedEngineFixture = (source, name) =>
  namedFixture(source, name).encoded;

export async function pinnedEngineContracts(root, requested = [
  'registered_body',
  'registered_values',
  'registered_fragment',
]) {
  if (!Array.isArray(requested) || requested.length === 0) {
    fail('InvalidPinnedEngineFixtureRequest', 'request');
  }
  const [source, aoaText] = await Promise.all([
    readFile(join(root,
      'src/query_integration/pinned_engine_contracts_wbtest.mbt'), 'utf8'),
    readFile(join(root, 'spec/contracts/actql-aoa.json'), 'utf8'),
  ]);
  const aoa = JSON.parse(aoaText);
  const registry = JSON.parse(await readFile(
    join(root, aoa.pipeline_registry_file), 'utf8'));
  const expected = Object.freeze({
    registered_body: Object.freeze({
      value: registry,
      cid: aoa.pipeline_registry_cid,
    }),
    registered_values: Object.freeze({
      value: aoa.execution_contracts['REL.values'],
      cid: aoa.target_registry_requirements['REL.values'].execution_contract.cid,
    }),
    registered_ordered: Object.freeze({
      value: aoa.execution_contracts['REL.derive.ordered'],
      cid: registry['REL.derive'].execution_extensions.ordered_bindings.cid,
    }),
    registered_fragment: Object.freeze({
      value: aoa.execution_contracts['ACTQL.expression_fragment/0.1'],
      cid: registry['ACTQL.expression_fragment/0.1'].execution_contract.cid,
    }),
  });
  return requested.map(name => {
    const fixture = namedFixture(source, name);
    if (!isDeepStrictEqual(fixture.value, expected[name].value)) {
      fail('PinnedEngineContractMismatch', name);
    }
    if (cid(fixture.value) !== expected[name].cid) {
      fail('PinnedEngineContractCidMismatch', name);
    }
    if (fixture.value.version !== names[name].version) {
      fail('PinnedEngineContractVersionMismatch', name);
    }
    if (fixture.value.operation !== names[name].operation) {
      fail('PinnedEngineContractOperationMismatch', name);
    }
    return fixture.encoded;
  });
}
