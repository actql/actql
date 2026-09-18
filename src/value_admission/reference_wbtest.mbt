///|
fn reference_limits(bytes? : Int = 4096) -> ReferenceLimits {
  { max_bytes: bytes, max_nodes: 64, max_depth: 4, max_text_units: 4096, }
}

///|
fn reference_contract(text : String) -> @contract.Contract {
  let node = @source.parse_json(
    text,
    { max_input_bytes: 4096, max_nodes: 64, max_depth: 8, },
    source_path="reference-contract.json",
  ).unwrap()
  let cursor = @decode.admit(node, {
    max_nodes: 64,
    max_depth: 8,
    max_string_bytes: 4096,
    max_total_string_bytes: 4096,
  }).unwrap()
  @contract.read_checked(cursor, {
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 4096,
  }).unwrap()
}

///|
fn resource_reference_wire() -> String {
  "{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"mail\",\"resource_kind\":\"mail/message\",\"version\":\"actql-resource-ref/0.1\"}"
}

///|
fn artifact_reference_wire() -> String {
  "{\"$actql_ref\":\"artifact\",\"artifact_ref_cid\":\"sha256:15e902418023a2de574d29d716f3b643825e19afa1fa3a5a46e049ffb1606eff\",\"media_type\":\"application/json\",\"metadata\":{\"artifact_store_id\":\"fixture\",\"availability_evidence_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"issuer_evidence\":{},\"media_type\":\"application/json\",\"retention_class\":\"fixture\",\"size_bytes\":3,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-artifact-ref/0.1\"}"
}

///|
fn reference_value_cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(
    text,
    { max_input_bytes: 20000, max_nodes: 200, max_depth: 20, },
    source_path="reference-value.json",
  ).unwrap()
  @decode.admit(node, {
    max_nodes: 200,
    max_depth: 20,
    max_string_bytes: 20000,
    max_total_string_bytes: 20000,
  }).unwrap()
}

///|
test "Host issuer admits canonical resource references without author access" {
  let expected = resource_reference_wire()
  let live = Ref(true)
  let issuer = bind_reference_issuer((_, wire) => wire == expected, _ => {
    live.val
  })
  let resource = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let checked = issue_reference(issuer, resource, expected, reference_limits()).unwrap()
  guard checked.value is Reference(reference) else { abort("reference value") }
  assert_eq(
    reference_identity_cid(reference),
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_true(reference_available(reference))
  let output = @encode.writer(expected.length(), 9, 1)
  emit_wire_value(checked.value, output)
  assert_eq(@encode.finish(output), expected)
  live.val = false
  assert_false(reference_available(reference))
}

///|
test "reissuance preserves the exact authority handle" {
  let expected = resource_reference_wire()
  let live = Ref(true)
  let contract = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let source = issue_reference(
    bind_reference_issuer((_, wire) => wire == expected, _ => live.val),
    contract,
    expected,
    reference_limits(),
  ).unwrap()
  guard source.value is Reference(original) else { abort("source reference") }
  let used = Ref(false)
  let reissuer = bind_reference_reissuer((required, wire) => {
    if !used.val && wire == expected && reference_compatible(original, required) {
      used.val = true
      Some(original)
    } else {
      None
    }
  })
  let checked = issue_reference(
    reissuer,
    contract,
    expected,
    reference_limits(),
  ).unwrap()
  guard checked.value is Reference(reissued) else {
    abort("reissued reference")
  }
  assert_true(reference_same_issuer(original, reissued))
  live.val = false
  assert_false(reference_available(reissued))
}

///|
test "reference issuance rejects foreign contracts wires and authority" {
  let expected = resource_reference_wire()
  let resource = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let wrong = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/thread\"}",
  )
  let issuer = bind_reference_issuer((_, wire) => wire == expected, _ => true)
  assert_true(
    issue_reference(issuer, wrong, expected, reference_limits())
    is Err(ContractMismatch),
  )
  let reordered = "{\"version\":\"actql-resource-ref/0.1\",\"$actql_ref\":\"resource\",\"resource_kind\":\"mail/message\",\"provider_namespace\":\"mail\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"}"
  assert_true(
    issue_reference(issuer, resource, reordered, reference_limits())
    is Err(NonCanonicalWire),
  )
  assert_true(
    issue_reference(
      bind_reference_issuer((_, _) => false, _ => true),
      resource,
      expected,
      reference_limits(),
    )
    is Err(IssuerRejected),
  )
  assert_true(
    issue_reference(
      bind_reference_issuer((_, _) => true, _ => false),
      resource,
      expected,
      reference_limits(),
    )
    is Err(Unauthorized),
  )
  assert_true(
    issue_reference(
      issuer,
      resource,
      expected,
      reference_limits(bytes=expected.length() - 1),
    )
    is Err(InvalidWire),
  )
}

///|
test "Host issuer validates artifact envelopes and media constraints" {
  let expected = artifact_reference_wire()
  let exact = reference_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let any = reference_contract("{\"type\":\"artifact_ref\",\"nullable\":false}")
  let wrong = reference_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"text/plain\"}",
  )
  let validated = Ref(0)
  let issuer = bind_reference_issuer(
    (contract, wire) => {
      validated.val += 1
      wire == expected && contract.shape is @contract.ArtifactRef(..)
    },
    _ => true,
  )
  for contract in [exact, any] {
    let checked = issue_reference(
      issuer,
      contract,
      expected,
      reference_limits(bytes=8192),
    ).unwrap()
    guard checked.value is Reference(reference) else {
      abort("artifact reference")
    }
    assert_eq(
      reference_identity_cid(reference),
      "sha256:15e902418023a2de574d29d716f3b643825e19afa1fa3a5a46e049ffb1606eff",
    )
  }
  assert_eq(validated.val, 2)
  assert_true(
    issue_reference(issuer, wrong, expected, reference_limits(bytes=8192))
    is Err(ContractMismatch),
  )
  assert_eq(validated.val, 2)
}

///|
test "Host admission preserves nested references and revokes them with issuer" {
  let reference = "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}"
  let contract = reference_contract(
    "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{\"refs\":{\"type\":\"array\",\"nullable\":false,\"items\":" +
    reference +
    ",\"max_items\":2}}}",
  )
  let reference_wire = resource_reference_wire()
  let cursor = reference_value_cursor("{\"refs\":[" + reference_wire + "]}")
  let live = Ref(true)
  let issuer = bind_reference_issuer(
    (_, candidate) => candidate == reference_wire,
    _ => live.val,
  )
  let checked = admit_host(
    issuer,
    contract,
    cursor,
    { max_nodes: 100, max_depth: 10, max_text_bytes: 10000, },
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  guard checked.value is Object(fields) &&
    element_at(fields, 0) is Some(("refs", Array(items))) &&
    element_at(items, 0) is Some(Reference(value)) else {
    abort("nested reference")
  }
  assert_true(reference_available(value))
  live.val = false
  assert_false(reference_available(value))
  assert_true(
    admit(contract, cursor, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 10000,
    })
    is Err(ValueIssue(UnsupportedReference, ..)),
  )
}

///|
test "Host admission rejects invalid reference limits before issuer work" {
  let contract = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let called = Ref(false)
  let issuer = bind_reference_issuer(
    (_, _) => {
      called.val = true
      true
    },
    _ => true,
  )
  assert_true(
    admit_host(
      issuer,
      contract,
      reference_value_cursor(resource_reference_wire()),
      { max_nodes: 100, max_depth: 10, max_text_bytes: 10000, },
      { max_bytes: 4096, max_nodes: 0, max_depth: 4, max_text_units: 4096, },
    )
    is Err(ValueIssue(InvalidLimits, ..)),
  )
  assert_false(called.val)
}
