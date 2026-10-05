///|
fn reference_steps_cursor_preserving(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: 20000,
      max_nodes: 200,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 200,
      max_depth: 20,
      max_string_bytes: 20000,
      max_total_string_bytes: 20000,
    },
  ).unwrap()
}

///|
fn complete_reference_steps(
  value : ReferenceAdmission,
) -> Result[(CheckedValue, Int, Int), ReferenceIssue] {
  for _ in 0..<10000 {
    match advance_reference_admission(value) {
      ReferenceAdmissionContinue => ()
      ReferenceAdmissionComplete(checked, nodes, text) =>
        return Ok((checked, nodes, text))
      ReferenceAdmissionFailed(issue) => return Err(issue)
      ReferenceAdmissionTerminal => abort("premature reference terminal")
    }
  }
  abort("reference admission did not terminate")
}

///|
test "resumed reference issuance retains exact envelope usage and original authority" {
  let resource = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let wire = resource_reference_wire()
  let live = Ref(true)
  let issuer = bind_reference_issuer((_, candidate) => candidate == wire, _ => {
    live.val
  })
  let admission = start_reference_admission(
    issuer,
    resource,
    reference_value_cursor(wire),
    reference_limits(),
  ).unwrap()
  let (checked, nodes, text) = complete_reference_steps(admission).unwrap()
  assert_eq(nodes, 9)
  guard checked.value is Reference(source) else { abort("issued resource") }
  assert_eq(reference_wire(source), wire)
  assert_eq(
    reference_identity_cid(source),
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_true(reference_available(source))
  let original = issue_reference(issuer, resource, wire, reference_limits()).unwrap()
  guard original.value is Reference(original) else {
    abort("original resource")
  }
  assert_true(reference_same_issuer(original, source))
  let reissuer = bind_reference_reissuer((expected, candidate) => {
    if reference_compatible(source, expected) && candidate == wire {
      Some(source)
    } else {
      None
    }
  })
  let (reissued, re_nodes, re_text) = complete_reference_steps(
    start_reference_admission(
      reissuer,
      resource,
      reference_value_cursor(wire),
      reference_limits(),
    ).unwrap(),
  ).unwrap()
  guard reissued.value is Reference(reissued) else {
    abort("reissued resource")
  }
  assert_true(reference_same_issuer(source, reissued))
  assert_eq((re_nodes, re_text), (nodes, text))
  live.val = false
  assert_false(reference_available(reissued))
  assert_true(
    complete_reference_steps(
      start_reference_admission(
        reissuer,
        resource,
        reference_value_cursor(wire),
        reference_limits(),
      ).unwrap(),
    )
    is Err(Unauthorized),
  )
  cancel_reference_admission(admission)
  assert_true(
    advance_reference_admission(admission) is ReferenceAdmissionTerminal,
  )
  assert_eq(reference_wire(source), wire)
}

///|
test "resumed reference normalization preserves string data and rejects normalized key collision" {
  let artifact = reference_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let input = artifact_reference_wire().replace(
    old="\"issuer_evidence\":{}",
    new="\"issuer_evidence\":{\"e\\u0301\":[null,\"e\\u0301\\r\"],\"z\":1}",
  )
  let expected = artifact_reference_wire().replace(
    old="\"issuer_evidence\":{}",
    new="\"issuer_evidence\":{\"z\":1,\"é\":[null,\"e\u0301\\r\"]}",
  )
  let calls = Ref(0)
  let issuer = bind_reference_issuer(
    (_, wire) => {
      calls.val += 1
      wire == expected
    },
    _ => true,
  )
  let checked = complete_reference_steps(
    start_reference_admission(
      issuer,
      artifact,
      reference_steps_cursor_preserving(input),
      reference_limits(),
    ).unwrap(),
  ).unwrap()
  assert_eq(checked.1, 22)
  guard checked.0.value is Reference(value) else { abort("artifact reference") }
  assert_eq(reference_wire(value), expected)
  assert_eq(calls.val, 1)
  let collision = artifact_reference_wire().replace(
    old="\"issuer_evidence\":{}",
    new="\"issuer_evidence\":{\"e\\u0301\":1,\"é\":2}",
  )
  assert_true(
    complete_reference_steps(
      start_reference_admission(
        issuer,
        artifact,
        reference_steps_cursor_preserving(collision),
        reference_limits(),
      ).unwrap(),
    )
    is Err(InvalidWire),
  )
  assert_eq(calls.val, 1)
}

///|
test "resumed references validate current authorization only after complete bounded evidence" {
  let resource = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let wire = resource_reference_wire()
  let calls = Ref(0)
  let live = Ref(true)
  let issuer = bind_reference_issuer(
    (_, candidate) => {
      calls.val += 1
      candidate == wire
    },
    _ => live.val,
  )
  for
    limits in [
      { ..reference_limits(), max_nodes: 8, },
      { ..reference_limits(), max_depth: 0, },
      { ..reference_limits(), max_text_units: 0, },
      { ..reference_limits(), max_bytes: wire.length() - 1, },
    ] {
    assert_true(
      complete_reference_steps(
        start_reference_admission(
          issuer,
          resource,
          reference_value_cursor(wire),
          limits,
        ).unwrap(),
      )
      is Err(InvalidWire),
    )
  }
  assert_eq(calls.val, 0)
  let admission = start_reference_admission(
    issuer,
    resource,
    reference_value_cursor(wire),
    reference_limits(),
  ).unwrap()
  for _ in 0..<1000 {
    if admission.phase == ReferenceIssueValue {
      break
    }
    assert_true(
      advance_reference_admission(admission) is ReferenceAdmissionContinue,
    )
  }
  assert_true(admission.phase == ReferenceIssueValue)
  assert_eq(calls.val, 0)
  live.val = false
  assert_true(
    advance_reference_admission(admission)
    is ReferenceAdmissionFailed(Unauthorized),
  )
  assert_true(
    admission.admission is None &&
    admission.writer is None &&
    admission.emission is None &&
    admission.envelope is None &&
    admission.wire is None,
  )
  assert_eq(calls.val, 1)
}

///|
test "resumed Host typed references share contracts without granting ordinary data authority" {
  let resource = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"mail/message\"}",
  )
  let contract = @contract.array_contract(resource, nullable=false).unwrap()
  let wire = resource_reference_wire()
  let cursor = reference_value_cursor("[null," + wire + "]")
  let issuer = bind_reference_issuer((_, candidate) => candidate == wire, _ => {
    true
  })
  let limits : Limits = { max_nodes: 11, max_depth: 2, max_text_bytes: 4096, }
  let (checked, nodes, text) = finish_typed_steps(
    start_host_typed_admission(
      issuer,
      contract,
      cursor,
      limits,
      reference_limits(),
    ).unwrap(),
  ).unwrap()
  let prior = admit_host_usage(
    issuer,
    contract,
    cursor,
    limits,
    reference_limits(),
  ).unwrap()
  assert_eq(nodes, 11)
  assert_eq((nodes, text), (prior.1, prior.2))
  assert_eq(typed_steps_wire(checked), "[null," + wire + "]")
  assert_eq(typed_steps_wire(prior.0), "[null," + wire + "]")
  assert_true(
    finish_typed_steps(start_typed_admission(contract, cursor, limits).unwrap())
    is Err(ValueIssue(UnsupportedReference, ..)),
  )
  let writer = @encode.writer(4096, 64, 4)
  let emission = start_wire_emit(checked.value, writer)
  let mut previous = 0
  let mut steps = 0
  while true {
    let complete = advance_wire_emit(emission)
    let (_, nodes, _) = @encode.writer_progress(writer)
    assert_true(nodes >= previous && nodes - previous <= 1)
    previous = nodes
    steps += 1
    if complete {
      break
    }
    if steps > 1000 {
      abort("reference emission did not terminate")
    }
  }
  assert_eq(previous, 11)
  assert_true(steps > previous)
  assert_eq(@encode.finish(writer), "[null," + wire + "]")
}

///|
test "reference cancellation keeps source issuer and drops staged evidence" {
  let resource = reference_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let wire = resource_reference_wire()
  let cursor = reference_value_cursor(wire)
  let calls = Ref(0)
  let issuer = bind_reference_issuer(
    (_, candidate) => {
      calls.val += 1
      candidate == wire
    },
    _ => true,
  )
  let seen = Ref(0)
  for
    phase in [
      ReferenceCanonical,
      ReferenceWriter,
      ReferenceEmit,
      ReferenceFinishWire,
      ReferenceIssueValue,
    ] {
    let admission = start_reference_admission(
      issuer,
      resource,
      cursor,
      reference_limits(),
    ).unwrap()
    for _ in 0..<1000 {
      if admission.phase == phase {
        break
      }
      assert_true(
        advance_reference_admission(admission) is ReferenceAdmissionContinue,
      )
    }
    assert_true(admission.phase == phase)
    seen.val += 1
    cancel_reference_admission(admission)
    cancel_reference_admission(admission)
    assert_true(
      advance_reference_admission(admission) is ReferenceAdmissionTerminal,
    )
    assert_true(
      admission.admission is None &&
      admission.writer is None &&
      admission.emission is None &&
      admission.envelope is None &&
      admission.wire is None,
    )
    assert_eq(@decode.object_length(cursor), Some(8))
    assert_eq(calls.val, 0)
  }
  assert_eq(seen.val, 5)
  assert_true(
    complete_reference_steps(
      start_reference_admission(issuer, resource, cursor, reference_limits()).unwrap(),
    )
    is Ok(_),
  )
  assert_eq(calls.val, 1)
}
