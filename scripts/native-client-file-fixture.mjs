// Private physical input files for existing CLI Reader/custody cases only.
// Runtime library bodies are synthetic three-byte files and are never loaded.
import {createHash} from 'node:crypto';
import {mkdirSync, symlinkSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

// Independent delivery vectors also authored in
// src/run_publication_host/client_result_delivery_receipts_wbtest.mbt.
const first = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:653b739f7a85f39a048ed77fe1d38f8fc5e1edcf1ab50a867a83216e76a1d146\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"answer\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}";
const equal_bytes = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:18ac1e0d8d953ef2f6de009ebab351f57701ce6bf8396f277b8f8d8443df0403\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"other\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}";
const csv = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":5,\"delivered_sha256\":\"6667b2d1aab6a00caa5aee5af8ad9f1465e567abf1c209d15727d57b3e8f6e5f\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:659f0bcd37039369f9188ac716ca7435ba03ad98d3d0fd357d6a0196bc8a3f85\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"csv\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-result-delivery-receipt/0.1\"}";
const legacy = "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"delivered_byte_count\":4,\"delivered_sha256\":\"8888888888888888888888888888888888888888888888888888888888888888\",\"egress_admission_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"invocation_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"result_artifact_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_delivery_receipt_cid\":\"sha256:1b672f923a8f34e603d8246a3541922ccb1eedb4be8d1691f9a290d14fe1e2ea\",\"result_manifest_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"result_name\":\"answer\",\"run_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"serialization_contract_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"version\":\"actql-result-delivery-receipt/0.1\"}";

export function nativeClientFileFixture(namespace) {
  const output = join(namespace, 'output-verification');
  mkdirSync(output, {mode: 0o700});
  const write = (path, body) => writeFileSync(path, body, {mode: 0o600, flag: 'wx'});
  write(join(output, 'data.bin'), 'data');
  write(join(output, 'changed.bin'), 'xxxx');
  write(join(output, 'single.json'), first);
  write(join(output, 'multiple.json'), `[${first},${equal_bytes},${csv},${legacy}]`);
  write(join(output, 'invalid.json'), `[${first},{}]`);
  write(join(output, 'empty.json'), '[]');

  const runtime = join(namespace, 'runtime-namespace');
  mkdirSync(runtime, {mode: 0o700});
  const digest = value => createHash('sha256').update(value).digest('hex');
  const members = [
    'lib/sqlite.bin', 'lib/crypto.bin',
    ...['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy']
      .map(role => `data/${role}.json`),
    'licenses/fixture.txt',
  ];
  const extent = path => ({path, bytes: 3, sha256: digest('abc')});
  const manifest = JSON.stringify({sourceSha: 'a'.repeat(40), platform: 'darwin-arm64',
    libraries: ['sqlite', 'crypto'].map(role => ({role, ...extent(`lib/${role}.bin`),
      license: 'licenses/fixture.txt', dependencies: ['/usr/lib/libSystem.B.dylib'],
      abi: {minimumMacOS: '14.0'}})),
    assets: ['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy']
      .map(role => ({role, ...extent(`data/${role}.json`)})),
    licenses: [extent('licenses/fixture.txt')]});
  for (const name of ['unchanged', 'root-replaced', 'child-replaced', 'mode-changed',
    'files-unchanged', 'files-sqlite-overwrite', 'files-crypto-mode',
    'files-environment-overwrite', 'files-policy-mode']) {
    const directory = join(runtime, name);
    mkdirSync(directory, {mode: 0o700});
    for (const child of ['lib', 'data', 'licenses']) mkdirSync(join(directory, child), {mode: 0o700});
    for (const member of members) write(join(directory, member), 'abc');
    write(join(directory, 'local-runtime.json'), manifest);
  }
  symlinkSync('unchanged', join(runtime, 'alias'), 'dir');
  // Deliberately do not create never-acquired: its missing original is tested.
  return {ACTQL_TEST_NATIVE_OUTPUT_VERIFY_ROOT: output,
    ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_ROOT: runtime,
    ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_MANIFEST_SHA256: digest(manifest)};
}
