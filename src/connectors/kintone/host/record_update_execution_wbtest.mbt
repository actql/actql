///|
fn update_execution_mapping() -> RecordUpdateMapping {
  prepare_record_update_mapping(
    update_mapping_declaration(update_mapping_form()),
    "inquiries",
    update_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
}

///|
fn update_execution_values() -> Bytes {
  b"{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"]}"
}

///|
fn update_execution_target() -> Bytes {
  b"{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"9007199254740993\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9007199254740994\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[\"old\"]},\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"server\"}}],\"totalCount\":null}"
}

///|
fn update_execution_proposal(
  mapping : RecordUpdateMapping,
) -> RecordUpdateProposal {
  prepare_record_update_proposal(
    mapping,
    "9007199254740993",
    update_execution_values(),
    8192,
    create_construction_write(16),
    create_construction_request(),
  ).unwrap()
}

///|
fn update_execution_pages() -> @catalog.RecordPageLimits {
  {
    max_bytes: 8192,
    max_nodes: 1000,
    max_depth: 16,
    max_rows: 1,
    max_columns: 8,
    max_cells: 32,
    max_table_rows: 16,
  }
}

///|
fn update_execution_value_limits() -> @catalog.RecordValueLimits {
  {
    max_columns: 8,
    max_name_bytes: 128,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
  }
}

///|
fn update_execution_preview(
  proposal : RecordUpdateProposal,
) -> RecordUpdatePreview {
  prepare_record_update_preview(
    proposal,
    update_execution_target(),
    update_execution_pages(),
    update_execution_value_limits(),
    create_construction_request(),
  ).unwrap()
}

///|
test "mapped UPDATE binds original proposal target revision and exact native body after observation" {
  let mapping = update_execution_mapping()
  let proposal = update_execution_proposal(mapping)
  assert_true(record_update_proposal_matches_mapping(proposal, mapping))
  assert_eq(record_update_proposal_identity(proposal), "9007199254740993")
  assert_eq(
    record_update_proposal_value_wire(proposal),
    "{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"]}",
  )
  let preview = update_execution_preview(proposal)
  assert_true(record_update_preview_matches(preview, proposal))
  assert_eq(record_update_preview_identity(preview), "9007199254740993")
  assert_eq(record_update_preview_revision(preview), "9007199254740994")
  let before = record_update_preview_before_wire(preview)
  assert_true(before.contains("\"Subject\":\"original\""))
  assert_true(before.contains("\"Computed\":\"server\""))
  assert_true(record_update_preview_version_cid(preview).has_prefix("sha256:"))
  let request = finalize_record_update_request(
    proposal,
    preview,
    create_construction_request(),
  ).unwrap()
  assert_true(record_update_execution_matches(proposal, preview, request))
  assert_eq(
    @catalog.record_update_request_body(request),
    "{\"app\":\"12\",\"records\":[{\"id\":\"9007199254740993\",\"record\":{\"Subject\":{\"value\":\"next 東京\"},\"Tags\":{\"value\":[\"東京\",\"red\",\"東京\"]}},\"revision\":\"9007199254740994\"}],\"upsert\":false}",
  )
}

///|
test "mapped UPDATE refuses copied and cross-original proposal and target material" {
  let mapping = update_execution_mapping()
  let proposal = update_execution_proposal(mapping)
  let preview = update_execution_preview(proposal)
  let copied_mapping : RecordUpdateMapping = { ..mapping, }
  let copied_proposal : RecordUpdateProposal = { ..proposal, }
  let copied_preview : RecordUpdatePreview = { ..preview, }
  assert_false(record_update_proposal_matches_mapping(proposal, copied_mapping))
  assert_false(record_update_proposal_matches_mapping(copied_proposal, mapping))
  assert_false(record_update_preview_matches(copied_preview, proposal))
  assert_false(record_update_preview_matches(preview, copied_proposal))
  for
    pair in [
      (copied_proposal, preview),
      (proposal, copied_preview),
      (update_execution_proposal(mapping), preview),
    ] {
    assert_true(
      finalize_record_update_request(
        pair.0,
        pair.1,
        create_construction_request(),
      )
      is Err(TargetMismatch),
    )
  }
  assert_true(
    prepare_record_update_proposal(
      copied_mapping,
      "9007199254740993",
      update_execution_values(),
      8192,
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(MappingMismatch),
  )
}

///|
test "mapped UPDATE retains full declared before columns and exact target selection" {
  let proposal = update_execution_proposal(update_execution_mapping())
  let original = @utf8.decode(update_execution_target())
  for
    wire in [
      original.replace(old="9007199254740993", new="9007199254740992"),
      "{\"records\":[],\"totalCount\":null}",
    ] {
    assert_true(
      prepare_record_update_preview(
        proposal,
        @utf8.encode(wire),
        update_execution_pages(),
        update_execution_value_limits(),
        create_construction_request(),
      )
      is Err(_),
    )
  }
  let missing = original.replace(
    old=",\"Computed\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"server\"}",
    new="",
  )
  assert_true(
    prepare_record_update_preview(
      proposal,
      @utf8.encode(missing),
      update_execution_pages(),
      update_execution_value_limits(),
      create_construction_request(),
    )
    is Err(_),
  )
  for
    wire in [
      b"{\"Subject\":\"next\"}", b"{\"Subject\":\"next\",\"Tags\":[],\"Computed\":\"spoofed\"}",
      b"{\"Subject\":\"next\",\"Subject\":\"other\",\"Tags\":[]}",
    ] {
    assert_true(
      prepare_record_update_proposal(
        proposal.mapping,
        "9007199254740993",
        wire,
        8192,
        create_construction_write(16),
        create_construction_request(),
      )
      is Err(_),
    )
  }
}

///|
test "mapped UPDATE preserves independent input target value and output bounds" {
  let mapping = update_execution_mapping()
  let bytes = update_execution_values()
  for maximum in [0, bytes.length() - 1] {
    assert_true(
      prepare_record_update_proposal(
        mapping,
        "9007199254740993",
        bytes,
        maximum,
        create_construction_write(16),
        create_construction_request(),
      )
      is Err(_),
    )
  }
  for identity in ["", "record-1", "-1"] {
    assert_true(
      prepare_record_update_proposal(
        mapping,
        identity,
        bytes,
        8192,
        create_construction_write(16),
        create_construction_request(),
      )
      is Err(TargetMismatch),
    )
  }
  let proposal = update_execution_proposal(mapping)
  let preview = update_execution_preview(proposal)
  assert_true(
    prepare_record_update_preview(
      proposal,
      update_execution_target(),
      {
        ..update_execution_pages(),
        max_bytes: update_execution_target().length() - 1,
      },
      update_execution_value_limits(),
      create_construction_request(),
    )
    is Err(_),
  )
  assert_true(
    prepare_record_update_preview(
      proposal,
      update_execution_target(),
      update_execution_pages(),
      { ..update_execution_value_limits(), max_nodes: 1, },
      create_construction_request(),
    )
    is Err(_),
  )
  assert_true(
    finalize_record_update_request(proposal, preview, {
      ..create_construction_request(),
      max_output_bytes: 1,
    })
    is Err(Request(@catalog.BudgetExceeded)),
  )
}

///|
test "mapped UPDATE cold restoration validates complete saved target values and body without I/O" {
  let mapping = update_execution_mapping()
  let proposal = update_execution_proposal(mapping)
  let preview = update_execution_preview(proposal)
  let original = finalize_record_update_request(
    proposal,
    preview,
    create_construction_request(),
  ).unwrap()
  let body = @catalog.record_update_request_body(original)
  let (restored_proposal, restored_preview, request) = restore_record_update_execution(
    mapping,
    "9007199254740993",
    update_execution_values(),
    update_execution_target(),
    body,
    8192,
    update_execution_pages(),
    update_execution_value_limits(),
    create_construction_write(16),
    create_construction_request(),
  ).unwrap()
  assert_true(
    record_update_execution_matches(
      restored_proposal, restored_preview, request,
    ),
  )
  assert_false(record_update_execution_matches(proposal, preview, request))
  assert_eq(@catalog.record_update_request_body(request), body)
  for
    changed in [
      body + " ",
      body.replace(old="9007199254740994", new="9"),
      body.replace(old="next 東京", new="foreign"),
    ] {
    assert_true(
      restore_record_update_execution(
        mapping,
        "9007199254740993",
        update_execution_values(),
        update_execution_target(),
        changed,
        8192,
        update_execution_pages(),
        update_execution_value_limits(),
        create_construction_write(16),
        create_construction_request(),
      )
      is Err(TargetMismatch),
    )
  }
  let changed_target = @utf8.encode(
    @utf8.decode(update_execution_target()).replace(
      old="9007199254740994",
      new="9",
    ),
  )
  assert_true(
    restore_record_update_execution(
      mapping,
      "9007199254740993",
      update_execution_values(),
      changed_target,
      body,
      8192,
      update_execution_pages(),
      update_execution_value_limits(),
      create_construction_write(16),
      create_construction_request(),
    )
    is Err(TargetMismatch),
  )
}

///|
test "mapped UPDATE typed response retains the same finalized native request" {
  let proposal = update_execution_proposal(update_execution_mapping())
  let preview = update_execution_preview(proposal)
  let request = finalize_record_update_request(
    proposal,
    preview,
    create_construction_request(),
  ).unwrap()
  let response = @catalog.project_record_update_acknowledgement(
    request,
    200,
    b"{\"records\":[{\"id\":\"9007199254740993\",\"revision\":\"9007199254740995\"}]}",
    create_construction_request(),
  ).unwrap()
  let outcome = @catalog.project_record_update_effect_outcome(
    request,
    response,
    create_construction_request(),
  ).unwrap()
  assert_true(
    @catalog.record_update_effect_outcome_matches_request(outcome, request),
  )
  assert_eq(
    @catalog.record_update_effect_outcome_wire(outcome),
    "{\"result\":{\"record_id\":\"9007199254740993\",\"revision\":\"9007199254740995\"},\"state\":\"applied\"}",
  )
  let other = finalize_record_update_request(
    proposal,
    preview,
    create_construction_request(),
  ).unwrap()
  assert_true(
    @catalog.project_record_update_effect_outcome(
      other,
      response,
      create_construction_request(),
    )
    is Err(@catalog.UncorrelatedResult),
  )
}
