import assert from 'node:assert/strict';
import test from 'node:test';
import {chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {copyConnectorAdditionHostSource, assertConnectorAdditionHostSource} from './connector-addition-source.mjs';

const repository = fileURLToPath(new URL('../',import.meta.url));
const temporary = t => {
  const root = mkdtempSync(join(tmpdir(),'actql-connector-common-source-'));
  t.after(() => rmSync(root,{recursive:true,force:true}));
  return root;
};
function fixture(t) {
  const root = temporary(t);
  for (const path of ['src/connectors_builtin/local_carrier_dispatch.mbt',
    'src/connectors_builtin_node/local_carrier_bridge.mbt','src/connectors_builtin_node/authorization_bridge.mbt',
    'src/connectors_builtin_node/client-program-dependencies.json','src/connectors_builtin_node/client-execution-dependencies.json']) {
    mkdirSync(dirname(join(root,path)),{recursive:true});writeFileSync(join(root,path),path);
  }
  return root;
}

test('connector isolation preserves the actual common Client declaration package and dependency manifests', t => {
  const destination = temporary(t);
  const inputs = copyConnectorAdditionHostSource(repository,destination);
  for (const path of ['src/connectors_builtin/local_carrier_dispatch.mbt',
    'src/connectors_builtin_node/local_carrier_bridge.mbt','src/connectors_builtin_node/authorization_bridge.mbt',
    'src/connectors_builtin_node/client_infer_bridge.mbt','src/connectors_builtin_node/client_model_generation_config.mbt',
    'src/connectors_builtin_node/client_infer_original_composed.mbt',
    'src/connectors_builtin_node/client_program_bridge.mbt',
    'src/connectors_builtin_node/client_installation_preparation_fields.generated.mbt',
    'src/connectors_builtin_node/client-program-dependencies.json','src/connectors_builtin_node/client-execution-dependencies.json']) {
    assert(inputs.some(input => input.path === path),'Missing retained original: '+path);
  }
  for (const {path} of inputs) {
    assert.deepEqual(readFileSync(join(destination,path)),readFileSync(join(repository,path)),path);
    assert.equal(lstatSync(join(destination,path)).mode & 0o777,lstatSync(join(repository,path)).mode & 0o777,path);
    assert.notEqual(lstatSync(join(destination,path)).ino,lstatSync(join(repository,path)).ino,path);
  }
  assert.equal(existsSync(join(destination,'_build')),false);
  assert.equal(existsSync(join(destination,'node_modules')),false);
  assert.equal(existsSync(join(destination,'src/connectors/reference_compute')),false);
  assert.equal(existsSync(join(destination,'src/connectors_builtin_node/bridge.generated.mbt')),false);
  assert.equal(existsSync(join(destination,'src/connectors_builtin_node/moon.pkg')),false);
  assert(readdirSync(join(destination,'src/connectors_builtin_node')).every(name => !/_(?:wb)?test\.mbt$/u.test(name)));
  assertConnectorAdditionHostSource(destination,inputs);
});

test('connector source copy retains other-owner generated production data but excludes tests and assembly outputs', t => {
  const root = fixture(t),destination = temporary(t),pkg = join(root,'src/connectors_builtin_node');
  for (const name of ['plain.mbt','fields.generated.mbt','bridge.generated.mbt','sample_test.mbt','sample_wbtest.mbt','moon.pkg','pkg.generated.mbti','unrelated.log']) {
    writeFileSync(join(pkg,name),Buffer.from([0,13,10,255]));
  }
  chmodSync(join(pkg,'plain.mbt'),0o640);
  const inputs = copyConnectorAdditionHostSource(root,destination);
  for (const name of ['plain.mbt','fields.generated.mbt']) assert(existsSync(join(destination,'src/connectors_builtin_node',name)));
  for (const name of ['bridge.generated.mbt','sample_test.mbt','sample_wbtest.mbt','moon.pkg','pkg.generated.mbti','unrelated.log']) {
    assert.equal(existsSync(join(destination,'src/connectors_builtin_node',name)),false,name);
  }
  assert.equal(lstatSync(join(destination,'src/connectors_builtin_node/plain.mbt')).mode & 0o777,0o640);
  assertConnectorAdditionHostSource(destination,inputs);
});

test('connector source preparation rejects a linked production member instead of following it', t => {
  const root = fixture(t),destination = temporary(t);
  writeFileSync(join(root,'foreign.mbt'),'foreign original');
  symlinkSync(join(root,'foreign.mbt'),join(root,'src/connectors_builtin_node/linked.mbt'));
  assert.throws(() => copyConnectorAdditionHostSource(root,destination),/Nonregular common Host source/u);
});

test('connector source preparation refuses a missing declared dependency manifest', t => {
  const root = fixture(t),destination = temporary(t);
  unlinkSync(join(root,'src/connectors_builtin_node/client-program-dependencies.json'));
  assert.throws(() => copyConnectorAdditionHostSource(root,destination),{code:'ENOENT'});
});

test('regeneration cannot alter retained common source bytes or original modes', t => {
  const root = fixture(t),destination = temporary(t);
  const inputs = copyConnectorAdditionHostSource(root,destination);
  const path = join(destination,'src/connectors_builtin_node/authorization_bridge.mbt');
  const bytes = readFileSync(path),mode = lstatSync(path).mode & 0o777;
  writeFileSync(path,'changed shared input');
  assert.throws(() => assertConnectorAdditionHostSource(destination,inputs),/Changed retained common Host source bytes/u);
  writeFileSync(path,bytes);chmodSync(path,mode ^ 0o100);
  assert.throws(() => assertConnectorAdditionHostSource(destination,inputs),/Changed retained common Host source mode/u);
  chmodSync(path,mode);
  assertConnectorAdditionHostSource(destination,inputs);
});
