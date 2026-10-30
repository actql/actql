///|
// Independent canonical preimages and SHA-256 values retain the published
// logical keys. The private observer counts issuance hashing only; it is not
// a count of external reader work or all hashing in a public operation.
test "issued Run evidence computes each original identity once" {
  {
    let calls = Ref(0)
    let issued = seal_run_evidence_value_with_identity(
      "logical_step_key",
      "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
      4096,
      64,
      8,
      (body, bytes, nodes, depth) => {
        calls.val += 1
        @json.cid_value(body, bytes, nodes, depth)
      },
    ).unwrap()
    assert_eq(calls.val, 1)
    assert_eq(
      run_evidence_value_identity(issued),
      "sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9",
    )
    assert_eq(
      run_evidence_value_json(issued),
      "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
    )
    assert_eq(
      run_evidence_value_json(
        seal_run_evidence_value(
          "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
          4096, 64, 8,
        ).unwrap(),
      ),
      run_evidence_value_json(issued),
    )
  }
  let calls = Ref(0)
  let issued = seal_run_evidence_value_with_identity(
    "logical_step_key",
    "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
    4096,
    64,
    8,
    (body, bytes, nodes, depth) => {
      calls.val += 1
      @json.cid_value(body, bytes, nodes, depth)
    },
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(
    run_evidence_value_identity(issued),
    "sha256:2ad8ff68dc3e793e262cc6efcb41ffb3d254795cd6780457fd04600cc09d8fbd",
  )
  assert_eq(
    run_evidence_value_json(issued),
    "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"self_cid\":\"sha256:2ad8ff68dc3e793e262cc6efcb41ffb3d254795cd6780457fd04600cc09d8fbd\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
  )
  assert_eq(
    run_evidence_value_json(
      seal_run_evidence_value(
        "logical_step_key", "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"kind\":\"operation\",\"operation_ordinal\":0},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
        4096, 64, 8,
      ).unwrap(),
    ),
    run_evidence_value_json(issued),
  )
}

///|
test "issued Run evidence keeps full wire limits and external identity refusal" {
  let body = "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}"
  let complete = "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"self_cid\":\"sha256:0ad21118174563ac8bcbdf62299659b71da72f6ef3b3ec9f42717d99fa4055e9\",\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}"
  let exact = seal_run_evidence_value("logical_step_key", body, 297, 8, 2).unwrap()
  assert_eq(run_evidence_value_json(exact), complete)
  assert_true(
    seal_run_evidence_value("logical_step_key", body, 296, 8, 2)
    is Err(RunEvidenceEncoding),
  )
  assert_true(
    seal_run_evidence_value("logical_step_key", body, 297, 7, 2) is Err(_),
  )
  assert_true(
    seal_run_evidence_value("logical_step_key", body, 297, 8, 1) is Err(_),
  )
  assert_true(
    admit_run_evidence_value("logical_step_key", complete, 297, 8, 2) is Ok(_),
  )
  let changed = complete.replace(
    old="\"stage_ordinal\":1",
    new="\"stage_ordinal\":2",
  )
  assert_true(
    admit_run_evidence_value("logical_step_key", changed, 297, 8, 2)
    is Err(RunEvidenceIdentityMismatch),
  )
  assert_true(
    seal_run_evidence_value("logical_step_key", complete, 4096, 64, 8)
    is Err(RunEvidenceIdentityAlreadyPresent),
  )
  assert_true(
    seal_run_evidence_value(
      "logical_step_key",
      body.replace(old="stage_ordinal", new="foreign_stage"),
      4096,
      64,
      8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "issued Run evidence propagates identity failure without issuing a value" {
  let calls = Ref(0)
  let failed = seal_run_evidence_value_with_identity(
    "logical_step_key",
    "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}",
    4096,
    64,
    8,
    (_, _, _, _) => {
      calls.val += 1
      raise @encode.OutputLimit
    },
  )
  assert_eq(calls.val, 1)
  assert_true(failed is Err(RunEvidenceEncoding))
}

///|
test "retained Run evidence usage preserves every narrower bound without rehashing" {
  let body = "{\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"occurrence\":{\"input_port_ordinal\":0,\"kind\":\"input_output\"},\"stage_ordinal\":1,\"version\":\"actql-logical-step-key/0.1\"}"
  let calls = Ref(0)
  let issued = seal_run_evidence_value_with_identity(
    "logical_step_key",
    body,
    4096,
    64,
    8,
    (value, bytes, nodes, depth) => {
      calls.val += 1
      @json.cid_value(value, bytes, nodes, depth)
    },
  ).unwrap()
  assert_eq(issued.wire_usage.unwrap(), (297, 8, 2))
  let unmeasured = { ..issued, wire_usage: None, }
  assert_false(run_evidence_value_fits(unmeasured, 4096, 64, 8))
  let wire = run_evidence_value_json(issued)
  let restored = admit_run_evidence_value("logical_step_key", wire, 4096, 64, 8).unwrap()
  assert_eq(restored.wire_usage.unwrap(), (297, 8, 2))
  for
    (bytes, nodes, depth) in [
      (297, 8, 2),
      (296, 8, 2),
      (297, 7, 2),
      (297, 8, 1),
      (0, 8, 2),
      (297, 0, 2),
      (297, 8, 0),
    ] {
    let expected = admit_run_evidence_value(
        "logical_step_key", wire, bytes, nodes, depth,
      )
      is Ok(_)
    assert_eq(run_evidence_value_fits(issued, bytes, nodes, depth), expected)
    assert_eq(run_evidence_value_fits(restored, bytes, nodes, depth), expected)
  }
  // Only this original issuer's identity calculation is observed. The old
  // external reader above remains an independent limit/identity boundary.
  assert_eq(calls.val, 1)
}
