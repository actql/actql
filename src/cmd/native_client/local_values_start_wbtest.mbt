///|
let cli_values_policy_original : String =
  #|{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}

///|
let cli_values_policy_cid : String = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"

///|
fn cli_values_installation_document(
  policy? : String = cli_values_policy_original,
  cid? : String = cli_values_policy_cid,
  extra? : (String, Json)? = None,
) -> String raise ClientStop {
  let assets = @run_host.client_local_product_assets()
  let fields = Map([
    ("registry", Json::string(assets.registry)),
    ("values", Json::string(assets.values)),
    ("result_policy_cid", Json::string(cid)),
    ("result_policy_wire", Json::string(policy)),
  ])
  if extra is Some((key, value)) {
    fields[key] = value
  }
  encode_request_json(Json::object(fields), 100000)
}

///|
fn cli_values_installation_refusal(document : String) -> String? {
  try {
    local_values_installation(local_input_cursor(document)) |> ignore
    None
  } catch {
    ClientStop(reason) => Some(reason)
  }
}

///|
test "CLI Values configuration retains exact unknown Policy without installing a Source" {
  let installed = local_values_installation(
    local_input_cursor(cli_values_installation_document()),
  )
  assert_eq(installed.result_policy_wire, cli_values_policy_original)
  assert_eq(installed.result_policy_cid, cli_values_policy_cid)
  let assets = @run_host.client_local_product_assets()
  assert_eq(installed._observed_registry_body, assets.registry)
  assert_eq(installed.values_body, assets.values)
  assert_true(installed.fragment_body is None)
  assert_true(installed.ordered_body is None)
  // Installed contract DATA is retained once; it grants no Source or execution authority.
}

///|
test "CLI Values configuration refuses changed Policy bytes and public reclassification" {
  for
    policy in [
      cli_values_policy_original.replace(old="unknown", new="public"),
      cli_values_policy_original.replace(old="true", new="false"),
    ] {
    assert_eq(
      cli_values_installation_refusal(cli_values_installation_document(policy~)),
      Some("InvalidLocalValuesResultPolicyOriginal"),
    )
  }
  assert_eq(
    cli_values_installation_refusal(
      cli_values_installation_document(cid="sha256:" + "a".repeat(64)),
    ),
    Some("InvalidLocalValuesResultPolicyOriginal"),
  )
}

///|
test "CLI Values configuration rejects null optional bodies unknown fields and oversized bodies" {
  for
    extra in [
      ("fragment", Json::null()),
      ("ordered", Json::number(1)),
      ("source", Json::string("invented-source")),
      ("values", Json::string("x".repeat(65537))),
    ] {
    assert_true(
      cli_values_installation_refusal(
        cli_values_installation_document(extra=Some(extra)),
      )
      is Some(_),
    )
  }
}

///|
test "CLI Values caller uses existing Native work publication and immutable policy retention" {
  // Matching Native caller compilation only; this does not open a Host/Store,
  // execute a CLI process, admit a read grant or prove installed acceptance.
  let caller : (
    @local_host.NativeLocalHostConnection,
    LocalHostSettings,
    LocalRunInstallation,
    @run_host.PreparedClientProgram,
    @run_host.ClientCompiledRun,
    @publication.PublicationContract,
    @run_host.ClientRequestIdentity,
    @local_host.NativeClientSubmissionReference,
    String,
    @local_crypto.Library,
    @local_store.Store,
    () -> Bool,
  ) -> String raise ClientStop = local_execute_publish_values
  caller |> ignore
}

///|
// Pure metadata definitions, compiler-only until matching Native execution.
test "current runtime asset selection keeps original Result Policy identity and bytes" {
  let current = @run_host.client_local_product_assets()
  let original : LocalValuesInstallation = {
    _observed_registry_body: current.registry,
    installed_contracts: @local_values.prepare_installed_sequence_contracts(
      current.registry,
      current.values,
      None,
      None,
    ).unwrap(),
    values_body: current.values,
    fragment_body: None,
    ordered_body: None,
    result_policy_cid: "sha256:" + "a".repeat(64),
    result_policy_wire: "original-policy\r\n",
  }
  let assets : @run_host.ClientLocalProductAssets = {
    ..current,
    result_policy: "original-policy\r\n",
  }
  let contracts = @local_values.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let installed = local_current_values_installation(original, assets, contracts)
  assert_true(physical_equal(installed.installed_contracts, contracts))
  assert_eq(installed._observed_registry_body, assets.registry)
  assert_eq(installed.values_body, assets.values)
  assert_eq(installed.result_policy_cid, "sha256:" + "a".repeat(64))
  assert_eq(installed.result_policy_wire, "original-policy\r\n")
  let rejected = try {
    local_current_values_installation(
      original,
      { ..assets, result_policy: "original-policy\n", },
      contracts,
    )
    |> ignore
    false
  } catch {
    ClientStop(_) => true
  }
  assert_true(rejected)
}

///|
// Exercise getter refusal and unacknowledged cleanup with the real opaque
// filesystem carrier. This does not directly recreate a post-open path race.
test "packaged runtime getter refusal retains unacknowledged cleanup" {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT").unwrap()
  let path = parent + "/runtime-constructor-pending"
  // The fixture seeds this invalid manifest before injecting Reader failures.
  guard @local_host.open_native_local_packaged_runtime(
      path,
      "a".repeat(40),
      "darwin-arm64",
      "b".repeat(64),
    )
    is Err(Pending(physical, _)) else {
    fail("diagnostic must retain the original pending cleanup carrier")
  }
  let stopped = try {
    local_packaged_runtime_from_physical(physical) |> ignore
    "unexpected-success"
  } catch {
    ClientStop(reason) => reason
  }
  assert_eq(stopped, "PackagedLocalRuntimeCleanupPending")
  assert_true(physical.check_current() is Err(Changed))
  assert_true(physical.close() is Err(CleanupPending))
}
