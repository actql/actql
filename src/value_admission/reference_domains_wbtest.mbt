///|
test "domain routing retains each original issuer and independent revocation" {
  let resource_wire = resource_reference_wire()
  let content_wire = content_reference_wire()
  let resource_contract = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let content_contract = reference_contract(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let resource_live = Ref(true)
  let content_live = Ref(true)
  let resource_calls = Ref(0)
  let content_calls = Ref(0)
  let resource_issuer = bind_reference_issuer(
    (contract, wire) => {
      resource_calls.val += 1
      contract.shape is @contract.ResourceRef(_) && wire == resource_wire
    },
    _ => resource_live.val,
  )
  let content_issuer = bind_reference_issuer(
    (contract, wire) => {
      content_calls.val += 1
      contract.shape is @contract.ContentRef(_) && wire == content_wire
    },
    _ => content_live.val,
  )
  let routed = bind_reference_domains(resource_issuer, content_issuer)
  let original_resource = issue_reference(
    resource_issuer,
    resource_contract,
    resource_wire,
    reference_limits(),
  ).unwrap()
  let original_content = issue_reference(
    content_issuer,
    content_contract,
    content_wire,
    reference_limits(),
  ).unwrap()
  resource_calls.val = 0
  content_calls.val = 0
  let resource = issue_reference(
    routed,
    resource_contract,
    resource_wire,
    reference_limits(),
  ).unwrap()
  assert_eq(resource_calls.val, 1)
  assert_eq(content_calls.val, 0)
  let content = issue_reference(
    routed,
    content_contract,
    content_wire,
    reference_limits(),
  ).unwrap()
  assert_eq(resource_calls.val, 1)
  assert_eq(content_calls.val, 1)
  guard original_resource.value is Reference(a) &&
    resource.value is Reference(b) &&
    original_content.value is Reference(c) &&
    content.value is Reference(d) else {
    abort("issued references")
  }
  assert_true(reference_same_issuer(a, b))
  assert_true(reference_same_issuer(c, d))
  assert_false(reference_same_issuer(b, d))
  resource_live.val = false
  assert_false(reference_available(b))
  assert_true(reference_available(d))
  assert_true(
    issue_reference(
      routed,
      resource_contract,
      resource_wire,
      reference_limits(),
    )
    is Err(Unauthorized),
  )
  content_live.val = false
  assert_false(reference_available(d))
  assert_true(
    issue_reference(routed, content_contract, content_wire, reference_limits())
    is Err(Unauthorized),
  )
}

///|
test "domain refusal cannot fall back to a permissive foreign issuer" {
  let resource = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let content = reference_contract(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let refused = bind_reference_issuer((_, _) => false, _ => true)
  let foreign_calls = Ref(0)
  let permissive = bind_reference_issuer(
    (_, _) => {
      foreign_calls.val += 1
      true
    },
    _ => true,
  )
  assert_true(
    issue_reference(
      bind_reference_domains(refused, permissive),
      resource,
      resource_reference_wire(),
      reference_limits(),
    )
    is Err(IssuerRejected),
  )
  assert_true(
    issue_reference(
      bind_reference_domains(permissive, refused),
      content,
      content_reference_wire(),
      reference_limits(),
    )
    is Err(IssuerRejected),
  )
  assert_eq(foreign_calls.val, 0)
}

///|
test "domain routing preserves exact reissued authority without reissuance fallback" {
  let wire = resource_reference_wire()
  let contract = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let live = Ref(true)
  let source = issue_reference(
    bind_reference_issuer((_, candidate) => candidate == wire, _ => live.val),
    contract,
    wire,
    reference_limits(),
  ).unwrap()
  guard source.value is Reference(original) else { abort("original reference") }
  let reissuer = bind_reference_reissuer((required, candidate) => {
    if candidate == wire && reference_compatible(original, required) {
      Some(original)
    } else {
      None
    }
  })
  let routed = bind_reference_domains(
    reissuer,
    bind_reference_issuer((_, _) => true, _ => true),
  )
  let result = issue_reference(routed, contract, wire, reference_limits()).unwrap()
  guard result.value is Reference(reissued) else { abort("reissued reference") }
  assert_true(reference_same_issuer(original, reissued))
  live.val = false
  assert_false(reference_available(reissued))
  assert_true(
    issue_reference(routed, contract, wire, reference_limits())
    is Err(Unauthorized),
  )
}

///|
test "resumed domain admission preserves envelope usage and selected authority" {
  for
    (contract, wire) in [
      (
        reference_contract(
          "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
        ),
        resource_reference_wire(),
      ),
      (
        reference_contract(
          "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
        ),
        content_reference_wire(),
      ),
    ] {
    let live = Ref(true)
    let selected = bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      live.val
    })
    let other = bind_reference_issuer((_, _) => false, _ => false)
    let routed = if contract.shape is @contract.ResourceRef(_) {
      bind_reference_domains(selected, other)
    } else {
      bind_reference_domains(other, selected)
    }
    let (before, nodes, text) = complete_reference_steps(
      start_reference_admission(
        selected,
        contract,
        reference_value_cursor(wire),
        reference_limits(),
      ).unwrap(),
    ).unwrap()
    let (after, routed_nodes, routed_text) = complete_reference_steps(
      start_reference_admission(
        routed,
        contract,
        reference_value_cursor(wire),
        reference_limits(),
      ).unwrap(),
    ).unwrap()
    guard before.value is Reference(a) && after.value is Reference(b) else {
      abort("resumed references")
    }
    assert_true(reference_same_issuer(a, b))
    assert_eq((routed_nodes, routed_text), (nodes, text))
    assert_eq(reference_wire(b), wire)
    live.val = false
    assert_false(reference_available(b))
    assert_true(
      complete_reference_steps(
        start_reference_admission(
          routed,
          contract,
          reference_value_cursor(wire),
          reference_limits(),
        ).unwrap(),
      )
      is Err(Unauthorized),
    )
  }
}
