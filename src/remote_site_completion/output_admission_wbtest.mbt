///|
fn cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="remote-output.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn output_owner() -> @lower.BoundPrepared {
  let checked = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"n\"]}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 20,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn request() -> @remote.DispatchRequest {
  @remote.prepare_dispatch_request(
    "coordinator-a",
    cid("0"),
    "task-a",
    1,
    "dispatch-a",
    "site-a",
    1,
    cid("a"),
    "local",
    "local/1",
    "strategy/1",
    cid("1"),
    cid("2"),
    cid("3"),
    cid("b"),
    cid("4"),
  ).unwrap()
}

///|
fn proof(
  request : @remote.DispatchRequest,
  measurement? : @remote.RemoteManagedOutputMeasurement,
  profile? : String,
) -> RemoteManagedOutputProof {
  let measurement = measurement.unwrap_or_else(() => {
    @remote.prepare_remote_managed_output_measurement(
      2,
      0,
      0,
      0,
      [2],
      [2],
      [2],
      [1],
      [0],
      [10],
    ).unwrap()
  })
  let holding = @remote.remote_output_holding_evidence_cid(
    request, "material-a", 8L,
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "material-a",
    holding,
    profile.unwrap_or(cid("3")),
    cid("5"),
    cid("6"),
    cid("7"),
    cid("8"),
    @remote.remote_managed_output_measurement_cid(measurement),
    2,
    8L,
  ).unwrap()
  let site = @site.create_site("site-a", 1, cid("a"), 4, 4, 1048576L, 1048576L).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    cid("a"),
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_managed_output_evidence_kind(),
    cid("b"),
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let (_, record) = @remote.commit_dispatch_acceptance(
    @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_provisioning(
      record,
      @remote.register_remote_execution_capability(
        site,
        cid("a"),
        "local",
        "local/1",
        "strategy/1",
        cid("4"),
      ).unwrap(),
    ).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_remote_execution(record).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_confirm_native_settled(record).unwrap(),
    true,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_retain_remote_output(record, "material-a", holding).unwrap(),
    true,
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  { evidence, subject, measurement, }
}

///|
fn expectation() -> RemoteManagedOutputExpectation {
  {
    managed_profile_cid: cid("3"),
    result_schema_cid: cid("5"),
    logical_view_cid: cid("6"),
    representation_codec_cid: cid("7"),
  }
}

///|
fn values(owner : @lower.BoundPrepared) -> @execution.ManagedOutputValues {
  @execution.prepare_managed_output_values(
    owner,
    @pipeline.Step(1),
    2,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    100,
    { max_work: 100, max_bytes: 1000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
}

///|
test "remote evidence finishes common aggregate value admission" {
  let owner = output_owner()
  let request = request()
  let port = prepare_remote_managed_output_verifier(
    values(owner),
    request,
    expectation(),
  ).unwrap()
  let receipt = finish_remote_managed_output_verifier(port, proof(request)).unwrap()
  assert_true(
    @execution.managed_output_value_receipt_matches(
      receipt,
      owner,
      @pipeline.Step(1),
    ),
  )
  assert_eq(@execution.managed_output_value_row_count(receipt), 2)
  assert_eq(@execution.managed_output_value_measurement(receipt), (4, 2, 2))
}

///|
test "remote aggregate admission rejects foreign and inconsistent proof" {
  for mode in 0..<4 {
    let request = request()
    let port = prepare_remote_managed_output_verifier(
      values(output_owner()),
      request,
      expectation(),
    ).unwrap()
    let candidate = match mode {
      0 =>
        proof(
          @remote.prepare_dispatch_request(
            "coordinator-a",
            cid("0"),
            "task-a",
            2,
            "dispatch-b",
            "site-a",
            1,
            cid("a"),
            "local",
            "local/1",
            "strategy/1",
            cid("1"),
            cid("2"),
            cid("3"),
            cid("b"),
            cid("4"),
          ).unwrap(),
        )
      1 => proof(request, profile=cid("9"))
      2 =>
        proof(
          request,
          measurement=@remote.prepare_remote_managed_output_measurement(
            2,
            0,
            0,
            0,
            [2, 2],
            [2, 2],
            [2, 2],
            [1, 1],
            [0, 0],
            [10, 10],
          ).unwrap(),
        )
      _ =>
        proof(
          request,
          measurement=@remote.prepare_remote_managed_output_measurement(
            2,
            0,
            0,
            0,
            [2],
            [2000],
            [2],
            [1],
            [0],
            [10],
          ).unwrap(),
        )
    }
    let result = finish_remote_managed_output_verifier(port, candidate)
    match mode {
      0 | 1 => assert_true(result is Err(Unverified))
      2 => assert_true(result is Err(InconsistentFacts))
      _ => assert_true(result is Err(OutputRepresentationRequired))
    }
  }
}
