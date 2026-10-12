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
  let fields = Map([
    ("registry", Json::string("original-registry")),
    ("values", Json::string("original-values")),
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
  assert_eq(installed.registry_body, "original-registry")
  assert_eq(installed.values_body, "original-values")
  assert_true(installed.fragment_body is None)
  assert_true(installed.ordered_body is None)
  // These strings are configuration metadata, not installed engine evidence.
  // The existing work Owner must admit their pinned originals before start.
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
  let original : LocalValuesInstallation = {
    registry_body: "old-registry",
    values_body: "old-values",
    fragment_body: Some("old-fragment"),
    ordered_body: Some("old-ordered"),
    result_policy_cid: "sha256:" + "a".repeat(64),
    result_policy_wire: "original-policy\r\n",
  }
  let assets : @run_host.ClientLocalProductAssets = {
    environment: "original-environment",
    registry: "current-registry",
    values: "current-values",
    fragment: "current-fragment",
    ordered: Some("current-ordered"),
    result_policy: "original-policy\r\n",
  }
  let installed = local_current_values_installation(original, assets)
  assert_eq(installed.registry_body, "current-registry")
  assert_eq(installed.values_body, "current-values")
  assert_eq(installed.result_policy_cid, "sha256:" + "a".repeat(64))
  assert_eq(installed.result_policy_wire, "original-policy\r\n")
  let rejected = try {
    local_current_values_installation(original, {
      ..assets,
      result_policy: "original-policy\n",
    })
    |> ignore
    false
  } catch {
    ClientStop(_) => true
  }
  assert_true(rejected)
}
