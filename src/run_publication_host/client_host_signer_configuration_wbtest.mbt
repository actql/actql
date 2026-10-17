///|
let host_signer_read_limits : ClientHostSignerReadLimits = {
  max_wire_bytes: 8192,
  max_nodes: 128,
  max_depth: 8,
  max_signers: 2,
}

///|
let host_signer_original : String =
  #|{"version":"actql-host/0.1","account_config":"./accounts.json","effect_policy":{"decision":"review"},"signers":{"ops-approver":{"principal":"ops","key_id":"ops-2026","private_key":"./keys/ops.pem","public_key":"./keys/ops.pub.pem","checkpoint_kinds":["effect_set"]}}}

///|
test "Host signers preserve the explicit original without issuing key authority" {
  let config = admit_client_host_signer_configuration(
    host_signer_original, host_signer_read_limits,
  ).unwrap()
  assert_eq(config.original_wire(), host_signer_original)
  assert_true(config.has_explicit_signers())
  assert_eq(config.signer_count(), 1)
  let signer = config.select_signer("ops-approver").unwrap()
  assert_eq(signer.name(), "ops-approver")
  assert_eq(signer.principal(), "ops")
  assert_eq(signer.key_id(), "ops-2026")
  assert_eq(signer.private_key_file(), "./keys/ops.pem")
  assert_eq(signer.public_key_file(), "./keys/ops.pub.pem")
  assert_true(signer.allows_kind(@checkpoint.EffectSet))
  assert_false(signer.allows_kind(@checkpoint.RunScope))
  assert_true(config.select_signer("OPS-APPROVER") is None)
  assert_true(config.signer_at(-1) is None)
  assert_true(config.signer_at(1) is None)
}

///|
test "missing and empty Host signers remain distinct without a fabricated default" {
  let missing = admit_client_host_signer_configuration(
    "{\"version\":\"actql-host/0.1\"}", host_signer_read_limits,
  ).unwrap()
  let empty = admit_client_host_signer_configuration(
    "{\"version\":\"actql-host/0.1\",\"signers\":{}}", host_signer_read_limits,
  ).unwrap()
  assert_false(missing.has_explicit_signers())
  assert_true(empty.has_explicit_signers())
  assert_eq(missing.signer_count(), 0)
  assert_eq(empty.signer_count(), 0)
  assert_true(missing.select_signer("local") is None)
  assert_true(empty.select_signer("local") is None)
}

///|
test "Host signers reject project and foreign roles rather than relabeling originals" {
  for
    wire in [
      host_signer_original.replace_all(old="actql-host/0.1", new="actql-config/0.1"),
      host_signer_original.replace_all(
        old="\"account_config\"",
        new="\"model_tasks\"",
      ),
      host_signer_original.replace_all(old="\"public_key\"", new="\"publicKey\""),
      host_signer_original.replace_all(old="\"effect_set\"", new="\"foreign\""),
      host_signer_original.replace_all(old="[\"effect_set\"]", new="[]"),
      host_signer_original.replace_all(
        old="[\"effect_set\"]",
        new="[\"effect_set\",\"effect_set\"]",
      ),
    ] {
    assert_true(
      admit_client_host_signer_configuration(wire, host_signer_read_limits)
      is Err(InvalidHostSignerConfiguration),
    )
  }
}

///|
test "Host signers reject missing null and wrong typed fields with no fallback" {
  for value in ["null", "false", "42", "[]", "\"\""] {
    assert_true(
      admit_client_host_signer_configuration(
        "{\"version\":\"actql-host/0.1\",\"signers\":" + value + "}",
        host_signer_read_limits,
      )
      is Err(InvalidHostSignerConfiguration),
    )
  }
  for
    field in [
      "principal", "key_id", "private_key", "public_key", "checkpoint_kinds",
    ] {
    // Every individual original field is required, including both key paths.
    let field_name = "\"" + field + "\""
    assert_true(
      admit_client_host_signer_configuration(
        host_signer_original.replace_all(old=field_name, new="\"missing\""),
        host_signer_read_limits,
      )
      is Err(InvalidHostSignerConfiguration),
    )
  }
  for value in ["null", "false", "42", "[]", "{}", "\"\"", "\"a\\u0000b\""] {
    assert_true(
      admit_client_host_signer_configuration(
        host_signer_original.replace_all(old="\"ops\"", new=value),
        host_signer_read_limits,
      )
      is Err(InvalidHostSignerConfiguration),
    )
  }
}

///|
test "Host signer projection keeps duplicate Unicode and JSON rejection" {
  for
    wire in [
      "{}",
      "null",
      "[]",
      host_signer_original + "{}",
      host_signer_original.replace_all(
        old="\"principal\":\"ops\"",
        new="\"principal\":\"ops\",\"principal\":\"other\"",
      ),
      host_signer_original.replace_all(
        old="\"principal\":\"ops\"",
        new="\"principal\":\"ops\",\"princi\\u0070al\":\"other\"",
      ),
      host_signer_original.replace_all(old="\"ops\"", new="\"\\ud800\""),
    ] {
    assert_true(
      admit_client_host_signer_configuration(wire, host_signer_read_limits)
      is Err(InvalidHostSignerConfiguration),
    )
  }
  let preserved = host_signer_original.replace_all(
    old="./keys/ops.pem",
    new="../鍵/é\r\n.pem",
  )
  // Literal line breaks are not valid JSON; they are never normalized away.
  assert_true(
    admit_client_host_signer_configuration(preserved, host_signer_read_limits)
    is Err(InvalidHostSignerConfiguration),
  )
  let wire = host_signer_original.replace_all(
    old="./keys/ops.pem",
    new="../鍵/é\\r\\n.pem",
  )
  let config = admit_client_host_signer_configuration(
    wire, host_signer_read_limits,
  ).unwrap()
  assert_eq(
    config.select_signer("ops-approver").unwrap().private_key_file(),
    "../鍵/é\r\n.pem",
  )
  assert_eq(config.original_wire(), wire)
}

///|
test "Host signer projection enforces explicit byte and cardinality ceilings" {
  let exact : ClientHostSignerReadLimits = {
    ..host_signer_read_limits,
    max_wire_bytes: @utf8.encode(host_signer_original).length(),
    max_signers: 1,
  }
  assert_true(
    admit_client_host_signer_configuration(host_signer_original, exact) is Ok(_),
  )
  assert_true(
    admit_client_host_signer_configuration(host_signer_original + " ", exact)
    is Err(HostSignerConfigurationLimit),
  )
  let two = host_signer_original.replace_all(
    old="\"ops-approver\":",
    new="\"other\":{\"principal\":\"other\",\"key_id\":\"other\",\"private_key\":\"private.pem\",\"public_key\":\"public.pem\",\"checkpoint_kinds\":[\"run_scope\"]},\"ops-approver\":",
  )
  assert_true(
    admit_client_host_signer_configuration(two, {
      ..host_signer_read_limits,
      max_signers: 1,
    })
    is Err(HostSignerConfigurationLimit),
  )
  let pair = admit_client_host_signer_configuration(
    two, host_signer_read_limits,
  ).unwrap()
  assert_eq(pair.signer_count(), 2)
  assert_eq(pair.signer_at(0).unwrap().name(), "other")
  assert_eq(pair.signer_at(1).unwrap().name(), "ops-approver")
  for
    limits in [
      { ..host_signer_read_limits, max_wire_bytes: 0, },
      { ..host_signer_read_limits, max_nodes: 0, },
      { ..host_signer_read_limits, max_depth: 0, },
      { ..host_signer_read_limits, max_signers: 0, },
    ] {
    assert_true(
      admit_client_host_signer_configuration(host_signer_original, limits)
      is Err(HostSignerConfigurationLimit),
    )
  }
}
