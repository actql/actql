///|
fn handling_policy_original() -> String {
  // Independent Node crypto over the literal envelope without its cid member.
  (
    #|{"body":{"accepted_classifications":["public","internal"],"allowed_regions":["explicit-region"],"retention":"none","training_use":"forbidden"},"cid":"sha256:4ae245d55eb9bcb462b0e709d9b7495429918caab5207eb27c3e359428ca3763","id":"operator-model-policy","kind":"request_data_handling","schema":"actql.contract/0.1","version":"operator-revision-1"}
  )
}

///|
fn handling_configuration(policy : String) -> String {
  "{\"model_defaults\":{\"default_model\":\"first\",\"models\":[{\"data_handling\":" +
  policy +
  ",\"generation_config\":{\"max_output_tokens\":100,\"temperature\":0,\"top_p\":1},\"model\":\"first\"},{\"generation_config\":{\"max_output_tokens\":200,\"temperature\":0,\"top_p\":1},\"model\":\"second\"}]}}"
}

///|
test "installed handling verifies the exact envelope and preserves its Task constraints" {
  let original = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let selected = resolve_model_provider_defaults(original, None, None, 1000).unwrap()
  let policy = resolved_model_provider_defaults_handling(selected, original).unwrap()
  assert_eq(
    model_provider_handling_identity(policy),
    "sha256:4ae245d55eb9bcb462b0e709d9b7495429918caab5207eb27c3e359428ca3763",
  )
  let writer = @encode.writer(10000, 100, 16)
  emit_model_provider_handling_original(policy, writer)
  assert_eq(@encode.finish(writer), handling_policy_original())
  let writer = @encode.writer(10000, 100, 16)
  emit_model_provider_handling(policy, writer)
  assert_eq(
    @encode.finish(writer),
    (
      #|{"accepted_classifications":["public","internal"],"allowed_regions":["explicit-region"],"contract_cid":"sha256:4ae245d55eb9bcb462b0e709d9b7495429918caab5207eb27c3e359428ca3763","retention":"none","training_use":"forbidden"}
    ),
  )
}

///|
test "installed handling is specific to the original configuration and selected model" {
  let original = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let selected = resolve_model_provider_defaults(original, None, None, 1000).unwrap()
  let equal = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  assert_true(
    resolved_model_provider_defaults_handling(selected, equal) is None,
  )
  let second = resolve_model_provider_defaults(
    original,
    Some("second"),
    None,
    1000,
  ).unwrap()
  assert_true(
    resolved_model_provider_defaults_handling(second, original) is None,
  )
  let legacy = default_profile_read(default_profile_configuration())
  let selected = resolve_model_provider_defaults(legacy, None, None, 1000).unwrap()
  assert_true(
    resolved_model_provider_defaults_handling(selected, legacy) is None,
  )
}

///|
test "installed handling rejects a changed body or role under a retained policy CID" {
  for
    policy in [
      handling_policy_original().replace(
        old="explicit-region",
        new="foreign-region",
      ),
      handling_policy_original().replace(
        old="request_data_handling",
        new="data_policy",
      ),
      handling_policy_original().replace(old="forbidden", new="allowed"),
      "null",
    ] {
    assert_true(
      read_model_provider_defaults_configuration(
        @utf8.encode(handling_configuration(policy)),
        default_profile_limits(),
        100000,
      )
      is Err(_),
    )
  }
}

///|
test "installed handling retains no-training nonempty and duplicate constraint refusals" {
  let limits = declaration_limits()
  for
    body in [
      (
        #|{"accepted_classifications":[],"allowed_regions":["r"],"retention":"none","training_use":"forbidden"}
      ),
      (
        #|{"accepted_classifications":["public","public"],"allowed_regions":["r"],"retention":"none","training_use":"forbidden"}
      ),
      (
        #|{"accepted_classifications":["public"],"allowed_regions":[],"retention":"none","training_use":"forbidden"}
      ),
      (
        #|{"accepted_classifications":["public"],"allowed_regions":["r","r"],"retention":"none","training_use":"forbidden"}
      ),
      (
        #|{"accepted_classifications":["public"],"allowed_regions":["r"],"retention":"unknown","training_use":"forbidden"}
      ),
      (
        #|{"accepted_classifications":["public"],"allowed_regions":["r"],"retention":"none","training_use":"allowed"}
      ),
    ] {
    let root = declaration_cursor(body)
    let budget : ModelTaskBudget = {
      limits,
      work: 0,
      contract_nodes: 0,
      contract_text: 0,
    }
    let result = try {
      let object = model_task_object(
        root,
        [
          "accepted_classifications", "allowed_regions", "retention", "training_use",
        ],
        budget,
      )
      ignore(
        model_task_handling_constraints(object, root, budget, "original-cid"),
      )
      true
    } catch {
      ModelTaskStop(_) => false
    }
    assert_false(result)
  }
}

///|
test "installed handling reserves bounded envelope hashing work before policy parsing" {
  let bytes = @utf8.encode(handling_configuration(handling_policy_original()))
  let limits = default_profile_limits()
  let (_, _, _, work) = read_model_provider_defaults_configuration(
    bytes, limits, 100000,
  ).unwrap()
  assert_true(
    read_model_provider_defaults_configuration(bytes, limits, work) is Ok(_),
  )
  assert_true(
    read_model_provider_defaults_configuration(bytes, limits, work - 1)
    is Err({ kind: WorkLimit, .. }),
  )
}
