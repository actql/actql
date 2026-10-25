import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import test from 'node:test';
import {mockChurnRiskCatalogue} from '../adapters/local-node/mock-churn-risk-catalogue.mjs';
import {checkMockChurnRiskCatalogue, renderMockChurnRiskCatalogue} from './mock-churn-risk-catalogue.mjs';

const originals = JSON.parse(readFileSync(new URL(
  '../src/client_row_source_host/mock_churn_risk_catalogue.json', import.meta.url), 'utf8'));

test('portable catalogue retains the complete previously authored Node DATA vector', () => {
  // Frozen from the complete original afc35c6411 asset, before this migration.
  assert.equal(createHash('sha256').update(JSON.stringify(originals)).digest('hex'),
    'bb73955bfa1c7e7eec5cc96fd2f7be0a7aeae2fc5e127a9dd7eaf69003690e13');
  assert.deepEqual(mockChurnRiskCatalogue, originals);
  assert.deepEqual(checkMockChurnRiskCatalogue(process.cwd()), [
    'adapters/local-node/mock-churn-risk-catalogue.mjs',
    'src/client_row_source_host/mock_churn_risk_catalogue.generated.mbt',
  ]);
});

test('catalogue generation refuses unknown fields and foreign or duplicate alias selection', () => {
  const changed = alter => {
    const value = structuredClone(originals); alter(value); return value;
  };
  for (const value of [
    changed(v => {v[0].authority = true;}),
    changed(v => {v[1].connection = v[0].connection;}),
    changed(v => {v[1].queryAliases[0].name = v[0].queryAliases[0].name;}),
    changed(v => {v[0].queryAliases[0].resource = 'foreign';}),
    changed(v => {v[0].views[0].schema_wire = undefined;}),
  ]) assert.throws(() => renderMockChurnRiskCatalogue(value));
});

test('ordinary catalogue freshness checks both outputs without repairing a stale asset', () => {
  mkdirSync('_build', {recursive: true});
  const directory = mkdtempSync(join(process.cwd(), '_build/mock-catalogue-generation-'));
  const input = join(directory, 'src/client_row_source_host/mock_churn_risk_catalogue.json');
  mkdirSync(join(directory, 'src/client_row_source_host'), {recursive: true});
  mkdirSync(join(directory, 'adapters/local-node'), {recursive: true});
  writeFileSync(input, JSON.stringify(originals));
  checkMockChurnRiskCatalogue(directory, true);
  for (const [path, expected] of renderMockChurnRiskCatalogue(originals)) {
    writeFileSync(join(directory, path), 'stale original');
    assert.throws(() => checkMockChurnRiskCatalogue(directory));
    assert.equal(readFileSync(join(directory, path), 'utf8'), 'stale original');
    writeFileSync(join(directory, path), expected);
  }
  checkMockChurnRiskCatalogue(directory);
});
