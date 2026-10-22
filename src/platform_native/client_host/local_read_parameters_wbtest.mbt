///|
fn read_parameters_fixture(
  name : String,
  wire : String,
  account_body? : Bytes = policy_account_original,
) -> (NativeLocalHostConnection, NativeLocalReadPolicyBinding) {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  let file = name + ".read.json"
  let writer = parent.create_writer(name + ".read.stage", 65536L).unwrap()
  writer.append(@utf8.encode(wire)).unwrap()
  writer.seal(file).unwrap() |> ignore
  let host = policy_host_fixture(name, files=[file], account_body~)
  let binding = host
    .bind_result_read_policy(epoch_test_crypto(), file, "operator", "cli")
    .unwrap()
  (host, binding)
}

///|
test "Native disclosure parameters preserve exact adopted purpose and ceiling without a read" {
  let wire = local_read_original_wire.replace_all(
    old="\"purpose\":\"inspection\"",
    new="\"purpose\":\"export\\u0301\\n\"",
  )
  let (host, binding) = read_parameters_fixture("read-parameters-exact", wire)
  let parameters = binding.disclosure_parameters()
  host.close().unwrap()
  let parameters = parameters.unwrap()
  assert_eq(parameters.purpose, "export\u0301\n")
  assert_eq(parameters.max_output_bytes, 65536)
  let retained = binding.disclosure_parameters().unwrap()
  assert_eq(retained.purpose, parameters.purpose)
  assert_eq(retained.max_output_bytes, parameters.max_output_bytes)
  assert_true(binding.require_current() is Err(Adoption(_)))
}

///|
test "Native disclosure parameters retain metadata while current rejects identical replacement generation" {
  let (disabled, binding) = read_parameters_fixture(
    "read-parameters-disabled",
    local_read_original_wire.replace_all(
      old="\"enabled\":true",
      new="\"enabled\":false",
    ),
  )
  let refusal = binding.disclosure_parameters()
  disabled.close().unwrap()
  assert_true(refusal is Err(Disabled))
  let name = "read-parameters-generation"
  let (host, binding) = read_parameters_fixture(name, local_read_original_wire)
  let before = binding.disclosure_parameters()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  let file = name + ".read.json"
  let generation = parent.inspect_generation(file).unwrap().unwrap()
  parent.reclaim_generation(file, generation).unwrap()
  let writer = parent
    .create_writer(name + ".replacement.stage", 65536L)
    .unwrap()
  writer.append(@utf8.encode(local_read_original_wire)).unwrap()
  writer.seal(file).unwrap() |> ignore
  let replaced = binding.disclosure_parameters().unwrap()
  let current = binding.require_current()
  host.close().unwrap()
  let before = before.unwrap()
  assert_eq(before.purpose, "inspection")
  assert_eq(replaced.purpose, before.purpose)
  assert_eq(replaced.max_output_bytes, before.max_output_bytes)
  assert_true(current is Err(Adoption(_)))
}

///|
test "Native disclosure metadata never substitutes for current RunRead or original expiry" {
  let account_body = @utf8.decode(policy_account_original).replace_all(
    old="[\"read\",\"submit\"]",
    new="[\"submit\"]",
  )
  let (host, binding) = read_parameters_fixture(
    "read-parameters-not-permission",
    local_read_original_wire,
    account_body=@utf8.encode(account_body),
  )
  let parameters = binding.disclosure_parameters().unwrap()
  let scope = host
    .authority_scope_cid("operator", "cli", epoch_test_crypto())
    .unwrap()
  let (original, _, _, definition) = journal_test_run(
    "parameters-request",
    "parameters-run",
    scope~,
  )
  let request : @result_access.NativeResultAccessRequest = {
    namespace_id: "original-namespace",
    authority_scope_cid: scope,
    run_definition_cid: @publication.publication_contract_identity(definition),
    principal_id: "operator",
    purpose: parameters.purpose,
    result_name: "answer",
    format: "jsonl",
    attempt_id: "explicit-read",
  }
  let denied = binding.authorize_read_request(
    original,
    request,
    "2026-10-11T00:00:00.000Z",
    max_output_bytes=Some(parameters.max_output_bytes),
  )
  let expired = binding.authorize_read_request(
    original,
    request,
    "2026-10-12T00:00:00.000Z",
    max_output_bytes=Some(parameters.max_output_bytes),
  )
  host.close().unwrap()
  assert_eq(parameters.purpose, "inspection")
  assert_eq(parameters.max_output_bytes, 65536)
  assert_true(denied is Err(Journal(AuthorizationDenied)))
  assert_true(expired is Err(PolicyExpired))
}
