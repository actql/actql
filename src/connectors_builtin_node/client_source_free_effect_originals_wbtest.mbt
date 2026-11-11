///|
// Reuse the independent finite STORE environment and original Host policy.
// This is static Common admission, not a physical grant, Preview or send.
fn source_free_effect_originals_fixture() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientEffectCompilation,
  @publication_host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @publication_host.ClientRequestIdentity,
) raise {
  let prepared = source_free_content_effect_fixture()
  let compilation = client_program_compile_local_effects_with_source_free_policy_body(
    prepared,
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    source_free_content_effect_policy(),
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = client_program_issue_allowed_effect_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = client_program_issue_effect_run_definition(
    allowed, "source-free-policy-scope", "source-free-policy-run", "2026-10-20T00:00:00.000Z",
    "2098-01-01T00:00:00.000Z",
  ).unwrap()
  let request = client_program_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "source-free-policy-request",
    client_program_source_free_input_intent_cid(),
  ).unwrap()
  (prepared, compilation, allowed, definition, request)
}

///|
fn source_free_original_replace(
  wire : String,
  name : String,
  replacement : Json?,
) -> String raise {
  guard @json.parse(wire) is Object(fields) else {
    abort("original test material must be an object")
  }
  fields.remove(name) |> ignore
  if replacement is Some(value) {
    fields[name] = value
  }
  @identity.stringify_value(
    @identity.from_json(Json::object(fields), 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
}

///|
fn source_free_original_admit(
  wire : String,
  plan : String,
) -> Result[
  @publication_host.ClientEffectPreparedOriginal,
  ClientEffectOriginalBridgeIssue,
] {
  client_program_admit_effect_prepared_original(
    wire, plan, false, false, true, false, false, false, false,
  )
}

///|
fn source_free_original_run_admit(
  wire : String,
  run : String,
  request : @publication_host.ClientRequestIdentity?,
) -> Result[
  @publication_host.ClientEffectRunMaterials,
  ClientEffectOriginalBridgeIssue,
] {
  client_program_admit_effect_run_materials(
    wire, run, false, false, true, false, false, false, false, request,
  )
}

///|
test "source-free Content originals retain the exact policy across prepared restoration" {
  let (_, compilation, _, _, _) = source_free_effect_originals_fixture()
  let original = client_program_issue_effect_prepared_original(compilation).unwrap()
  let expected = @publication.publication_contract_identity(
    @publication_host.client_effect_compilation_compiled_plan(compilation),
  )
  let held = source_free_original_admit(original, expected).unwrap()
  let restored = client_program_effect_prepared_original_compilation(held)
  assert_eq(
    client_program_issue_effect_prepared_original(restored).unwrap(),
    original,
  )
  assert_eq(
    client_program_effect_compilation_compiled_plan_wire(restored),
    client_program_effect_compilation_compiled_plan_wire(compilation),
  )
  guard @json.parse(original) is Object(fields) else { fail("original object") }
  assert_eq(
    fields.get("source_free_result_policy_cid"),
    Some(
      Json::string(
        "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      ),
    ),
  )
  assert_eq(
    fields.get("source_free_result_policy_json"),
    Some(Json::string(source_free_content_effect_policy())),
  )
  assert_false(
    physical_equal(
      @publication_host.client_effect_compilation_owner(compilation),
      client_program_effect_prepared_original_prepared(held),
    ),
  )
}

///|
test "source-free Content originals restore the same Run request and complete saved materials" {
  let (_, _, allowed, definition, request) = source_free_effect_originals_fixture()
  let original = client_program_issue_prepared_effect_run_materials(
    allowed,
    definition,
    Some(request),
  ).unwrap()
  let expected = @publication.publication_contract_identity(definition)
  let restored = source_free_original_run_admit(
    original,
    expected,
    Some(request),
  ).unwrap()
  assert_eq(restored.request, Some(request))
  assert_eq(
    @publication.publication_contract_json(restored.run_definition),
    @publication.publication_contract_json(definition),
  )
  assert_eq(
    client_program_issue_prepared_effect_run_materials(
      restored.allowed,
      restored.run_definition,
      restored.request,
    ).unwrap(),
    original,
  )
  guard @json.parse(original) is Object(fields) else { fail("material object") }
  assert_eq(
    fields.get("source_free_result_policy_json"),
    Some(Json::string(source_free_content_effect_policy())),
  )
}

///|
test "source-free Content originals refuse missing partial malformed and changed policy inputs" {
  let (_, compilation, allowed, definition, request) = source_free_effect_originals_fixture()
  let original = client_program_issue_effect_prepared_original(compilation).unwrap()
  let plan = @publication.publication_contract_identity(
    @publication_host.client_effect_compilation_compiled_plan(compilation),
  )
  let materials = client_program_issue_prepared_effect_run_materials(
    allowed,
    definition,
    Some(request),
  ).unwrap()
  let run = @publication.publication_contract_identity(definition)
  let mutate = fn(wire : String) -> Array[String] raise {
    let no_cid = source_free_original_replace(
      wire,
      "source_free_result_policy_cid",
      None,
    )
    [
      no_cid,
      source_free_original_replace(wire, "source_free_result_policy_json", None),
      source_free_original_replace(
        no_cid,
        "source_free_result_policy_json",
        None,
      ),
      source_free_original_replace(
        wire,
        "source_free_result_policy_cid",
        Some(Json::number(1)),
      ),
      source_free_original_replace(
        wire,
        "source_free_result_policy_json",
        Some(Json::null()),
      ),
      source_free_original_replace(
        wire,
        "source_free_result_policy_cid",
        Some(Json::string("sha256:" + "f".repeat(64))),
      ),
      source_free_original_replace(
        wire,
        "source_free_result_policy_json",
        Some(Json::string("{}")),
      ),
      source_free_original_replace(
        wire,
        "source_free_result_policy_json",
        Some(Json::string(" " + source_free_content_effect_policy())),
      ),
      source_free_original_replace(
        wire,
        "source_free_result_policy_json",
        Some(
          Json::string(
            source_free_content_effect_policy().replace(
              old="unknown",
              new="public",
            ),
          ),
        ),
      ),
      source_free_original_replace(
        wire,
        "source_free_result_policy_json",
        Some(Json::string("x".repeat(65537))),
      ),
    ]
  }
  for candidate in mutate(original) {
    assert_true(source_free_original_admit(candidate, plan) is Err(_))
  }
  for candidate in mutate(materials) {
    assert_true(
      source_free_original_run_admit(candidate, run, Some(request)) is Err(_),
    )
  }
}

///|
test "source-free Content originals never replace the independently selected Plan Run or request" {
  let (prepared, compilation, allowed, definition, request) = source_free_effect_originals_fixture()
  let original = client_program_issue_effect_prepared_original(compilation).unwrap()
  assert_true(
    source_free_original_admit(original, "sha256:" + "f".repeat(64)) is Err(_),
  )
  let materials = client_program_issue_prepared_effect_run_materials(
    allowed,
    definition,
    Some(request),
  ).unwrap()
  let run = @publication.publication_contract_identity(definition)
  assert_true(
    source_free_original_run_admit(
      materials,
      "sha256:" + "f".repeat(64),
      Some(request),
    )
    is Err(_),
  )
  assert_true(source_free_original_run_admit(materials, run, None) is Err(_))
  let missing_request = source_free_original_replace(
    materials,
    "client_request_identity",
    None,
  )
  assert_true(
    source_free_original_run_admit(missing_request, run, None) is Err(_),
  )
  assert_true(
    source_free_original_run_admit(missing_request, run, Some(request))
    is Err(_),
  )
  let foreign_request = client_program_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "foreign-source-free-policy-request",
    client_program_source_free_input_intent_cid(),
  ).unwrap()
  assert_true(
    source_free_original_run_admit(materials, run, Some(foreign_request))
    is Err(_),
  )
}

///|
test "Request Effect material bridge retains the same original compiler and complete Content policy" {
  let (prepared, compilation, allowed, definition, request) = source_free_effect_originals_fixture()
  let wire = client_program_issue_prepared_effect_run_materials(
    allowed,
    definition,
    Some(request),
  ).unwrap()
  let restored = client_program_admit_effect_run_materials_with_compilation(
    wire,
    @publication.publication_contract_identity(definition),
    compilation,
    request,
    false,
    false,
    true,
    false,
    false,
    false,
    false,
  ).unwrap()
  assert_true(physical_equal(restored.prepared, prepared))
  assert_true(physical_equal(restored.compilation, compilation))
  assert_eq(restored.request, Some(request))
  assert_eq(
    client_program_issue_prepared_effect_run_materials(
      restored.allowed,
      restored.run_definition,
      Some(request),
    ).unwrap(),
    wire,
  )
}

///|
test "Request Effect material bridge refuses a foreign Request without issuing another compiler" {
  let (prepared, compilation, allowed, definition, request) = source_free_effect_originals_fixture()
  let wire = client_program_issue_prepared_effect_run_materials(
    allowed,
    definition,
    Some(request),
  ).unwrap()
  let foreign = client_program_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "foreign-retained-request",
    client_program_source_free_input_intent_cid(),
  ).unwrap()
  assert_true(
    client_program_admit_effect_run_materials_with_compilation(
      wire,
      @publication.publication_contract_identity(definition),
      compilation,
      foreign,
      false,
      false,
      true,
      false,
      false,
      false,
      false,
    )
    is Err(Materials(Request(IdentityMismatch))),
  )
}
