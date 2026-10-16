// Freeze a real receiver output as test INPUT. Independent Command/Envelope
// identities are authored separately; no expected product result is generated.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const fixturePath='src/connectors/gcs/contract_acceptance/fixtures/command-environment-receiver.json';
const fixture=JSON.parse(readFileSync(fixturePath,'utf8'));
assert.equal(createHash('sha256').update(fixture.wire).digest('hex'),fixture.wireSha256);
assert.equal(Buffer.byteLength(fixture.wire),6894);
assert.equal(fixture.exportSuffix,'\n');
assert.ok(fixture.wire.endsWith(fixture.exportSuffix));
const runtimeWire=fixture.wire.slice(0,-fixture.exportSuffix.length);
assert.equal(Buffer.byteLength(runtimeWire),fixture.runtimeWireBytes);
assert.equal(createHash('sha256').update(runtimeWire).digest('hex'),fixture.runtimeWireSha256);
assert.equal(fixture.receiverSource,'723c00dbf0df0a59b9da9d06462358e704f0edca');
assert.equal(fixture.independentCommandCid,'sha256:01b4437a23e585b15309e958d28d7069d58f3f9002ec6fffe8458dc24b58fa39');
assert.equal(fixture.independentInputCid,'sha256:d15b2d1c7b0555836d28a967fa895f56ced810a056e4045c500e760181fa5fac');
const output=[
  '// Generated from the frozen real B receiver input; do not regenerate identities from product output.',
  `// Receiver ${fixture.receiverSource}; provider ${fixture.providerSource}.`,
  '', '///|', 'test "actual B GCS Command environment receiver output enters original Common" {',
  `  let wire = ${JSON.stringify(runtimeWire)}`,
  `  assert_true(@environment.read(@utf8.encode(wire + "\\n"),${JSON.stringify(fixture.evidenceCid)},caps()) is Err(@environment.NonCanonicalBytes))`,
  `  let original = match @environment.read(@utf8.encode(wire), ${JSON.stringify(fixture.evidenceCid)}, caps()) { Ok(value) => value; Err(issue) => { debug_inspect(issue, content="valid original receiver environment"); abort("original receiver rejected") } }`,
  '  let contents = catalogs(original)',
  '  let refs = references(contents)',
  '  let target = @environment.select_command_target(contents, "command:exports.gcs.upload.v1", 100000).unwrap()',
  `  assert_eq(@environment.command_target_cid(target), ${JSON.stringify(fixture.independentCommandCid)})`,
  '  let command = @decode.open_object(@environment.member_body(@environment.command_target_member(target))).unwrap()',
  '  let role = @environment.catalog_reference_for_cursor(refs, @decode.lookup(command, "input_schema").unwrap()).unwrap()',
  `  assert_eq(@environment.contract_identity(@environment.reference_contract(role)).2, ${JSON.stringify(fixture.independentInputCid)})`,
  '  let (input, _) = @environment.command_target_input_contract(target, refs, value_caps(), 100000).unwrap()',
  '  assert_eq(@environment.command_input_contract_field_count(input), 4)',
  '  for name in ["content", "name"] { assert_true(@environment.command_input_contract_field_required(input, name)) }',
  '  for name in ["content_type", "overwrite"] { assert_false(@environment.command_input_contract_field_required(input, name)) }',
  '  ignore(@environment.check_protocol_value_contracts(@environment.check_source_data_policies(refs, {max_work:100000,max_policies:100}).unwrap(), {max_envelopes:100,contracts:value_caps()}).unwrap())',
  '  let mapping = @environment.mapping_shape_at(@environment.check_mapping_contract_shapes(original,caps(),100000).unwrap(),0).unwrap()',
  '  let bound = @environment.bind_store_command(mapping,contents,100000).unwrap()',
  '  assert_eq(@environment.store_command_mapping_operation(bound),("create","none"))',
  `  assert_eq(@environment.command_target_cid(@environment.store_command_target(bound)),${JSON.stringify(fixture.independentCommandCid)})`,
  '  assert_true(physical_equal(@environment.member_environment(@environment.command_target_member(@environment.store_command_target(bound))),original))',
  '  let copied = @environment.read(@utf8.encode(wire),@environment.cid(original),caps()).unwrap()',
  '  assert_true(@environment.bind_store_command(mapping,catalogs(copied),100000) is Err(@environment.StoreCommandIssue::ForeignEnvironment))',
  '}', '',
].join('\n');
const target='src/connectors/gcs/contract_acceptance/command_environment_receiver.generated_test.mbt';
if(process.argv.includes('--write'))writeFileSync(target,output);
assert.equal(readFileSync(target,'utf8'),output);
console.log(JSON.stringify({exportedArtifactBytes:Buffer.byteLength(fixture.wire),exportedArtifactSha256:fixture.wireSha256,runtimeWireBytes:fixture.runtimeWireBytes,runtimeWireSha256:fixture.runtimeWireSha256,receiverSource:fixture.receiverSource,expectedIdentities:'independent C preimages; original export LF retained as strict negative, exact runtime prefix positive',writes:process.argv.includes('--write')}));
