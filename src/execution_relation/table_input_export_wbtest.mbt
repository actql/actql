///|
fn table_input_export_occurrence(
  owner : @lower.BoundPrepared,
  fields? : String = "[\"p\",\"id\"]",
) -> ManagedTableInputOccurrence {
  let declarations = @results.check_table_inputs(
    @lower.pipeline(@lower.bound_preparation(owner)),
    input_cursor("{\"material\":{\"from\":\"rows\",\"fields\":" + fields + "}}"),
    {
      max_results: 10,
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
  bind_managed_table_input_occurrence(owner, declarations, "material").unwrap()
}

///|
fn table_input_source_fixture(
  empty? : Bool = false,
) -> (@lower.BoundPrepared, CompletedOutput) raise {
  let owner = presence_output_owner()
  let admitted = prepare_admitted_output(
    owner,
    Step(0),
    3,
    stream_value_limits(),
  ).unwrap()
  if !empty {
    for wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
      append_admitted_output_wire(admitted, wire, retained_row_test_limits()).unwrap()
    }
  }
  let rows = finish_admitted_output(admitted).unwrap()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["events_0"],
    10000,
    1000,
  ).unwrap()
  let port = prepare_trusted_output_port(preparation, Step(0), 1000, 10000, (
    _ : Unit,
  ) => Some(rows)).unwrap()
  (owner, complete_trusted_output(port, ()).unwrap())
}

///|
fn table_input_export_start(
  source : CompletedOutput,
  occurrence : ManagedTableInputOccurrence,
  limits? : CompletedResultViewLimits = result_view_limits(),
) -> Result[CompletedTableInputRelationExportPreparation, CompletedExportIssue] {
  start_completed_table_input_relation_export(
    source,
    occurrence,
    limits,
    3,
    stream_value_limits(),
    row_wire_limits(),
    row_wire_limits(),
    publication_schema_limits(),
    64,
  )
}

///|
fn table_input_export_finish(
  preparation : CompletedTableInputRelationExportPreparation,
  quantum : Int,
) -> (CompletedRelationExportReceipt, String) raise {
  let mut ready = false
  for _ in 0..<100 {
    if advance_completed_table_input_relation_export(preparation, quantum).unwrap().0 {
      ready = true
      break
    }
  }
  assert_true(ready)
  let stream = finish_completed_table_input_relation_export_preparation(
    preparation,
  ).unwrap()
  let text = StringBuilder()
  while next_completed_output_export(stream).unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  let (receipt, tail) = finish_completed_relation_export(stream).unwrap()
  text.write_string(tail)
  (receipt, text.to_string())
}

///|
test "private Table export preserves three presence states with exact schema and bounded mapping" {
  for quantum in [1, 100] {
    let (owner, source) = table_input_source_fixture()
    let occurrence = table_input_export_occurrence(owner)
    let preparation = table_input_export_start(source, occurrence).unwrap()
    assert_true(
      completed_table_input_export_preparation_matches_owner(
        preparation, occurrence, source,
      ),
    )
    let (receipt, text) = table_input_export_finish(preparation, quantum)
    assert_eq(text, "[{\"id\":1,\"p\":7},{\"id\":2,\"p\":null},{\"id\":3}]")
    assert_eq(
      completed_relation_export_content(receipt).cid,
      "sha256:12df04cee2e595d5e54cc4baecdbde4436c2dbf10ac66a643cdbdc784833827a",
    )
    assert_eq(completed_relation_export_field_names(receipt), ["id", "p"])
    assert_eq(
      relation_schema_wire(completed_relation_export_schema_identity(receipt)),
      "{\"id\":{\"nullable\":false,\"type\":\"number\"},\"p\":{\"contract\":{\"nullable\":true,\"type\":\"number\"},\"presence\":\"conditional\"}}",
    )
    // Node crypto hashes the literal schema preimage, not product output.
    assert_eq(
      relation_schema_cid(completed_relation_export_schema_identity(receipt)),
      "sha256:10ce8369a6cadfefd6e712b9af9320c69915df75a0a9654c7d69788ef23a437c",
    )
    // Independently fixed: id matches column 0 (1), p matches column 1
    // after two probes (2), and final setup consumes one unit (1).
    assert_eq(completed_table_input_export_preparation_work(preparation), 4)
    assert_eq(completed_table_input_export_preparation_work(preparation), 4)
    assert_true(
      completed_table_input_export_preparation_matches_receipt(
        preparation, receipt,
      ),
    )
    assert_false(cancel_completed_table_input_relation_export(preparation))
    assert_true(completed_output_available(source))
    let retained = retain_admitted_output_stream(
      completed_relation_export_content(receipt),
      text,
      () => true,
    )
    let saved = bind_completed_output_export(
      receipt.rows,
      retained_output_material(retained),
    ).unwrap()
    let importing = prepare_completed_output_import(
      saved,
      3,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    for wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
      append_completed_output_import_wire(
        importing,
        wire,
        retained_row_test_limits(),
      ).unwrap()
    }
    let reloaded = finish_completed_output_import(importing).unwrap()
    assert_true(
      completed_presence_cell(reloaded, 0, 1)
      is Ok(Present(@admitted.Number(7))),
    )
    assert_true(
      completed_presence_cell(reloaded, 1, 1) is Ok(Present(@admitted.Null)),
    )
    assert_true(completed_presence_cell(reloaded, 2, 1) is Ok(Absent))
    assert_true(completed_cell(reloaded, 0, 1) is None)
  }
}

///|
test "private Table export projects closed fields and retains empty declared presence" {
  for empty in [false, true] {
    let (owner, source) = table_input_source_fixture(empty~)
    let occurrence = table_input_export_occurrence(owner, fields="[\"p\"]")
    let preparation = table_input_export_start(source, occurrence).unwrap()
    let (receipt, text) = table_input_export_finish(preparation, 1)
    assert_eq(text, if empty { "[]" } else { "[{\"p\":7},{\"p\":null},{}]" })
    assert_eq(completed_relation_export_field_names(receipt), ["p"])
    assert_eq(
      relation_schema_wire(completed_relation_export_schema_identity(receipt)),
      "{\"p\":{\"contract\":{\"nullable\":true,\"type\":\"number\"},\"presence\":\"conditional\"}}",
    )
    assert_eq(
      relation_schema_cid(completed_relation_export_schema_identity(receipt)),
      "sha256:a3449debd2dfde6dcf5f49a4b359251aed6607540edbff9699ef33a82ec00406",
    )
    if !empty {
      assert_eq(
        completed_relation_export_content(receipt).cid,
        "sha256:6b1c482cd0bb4352609f2a885f27459ce4aee11764cbb2d323ac3f556f2fd2d3",
      )
    }
    assert_eq(completed_table_input_export_preparation_work(preparation), 3)
  }
}

///|
test "private Table export rejects foreign checked occurrence and keeps borrowed source on failure" {
  let (owner, source) = table_input_source_fixture()
  let occurrence = table_input_export_occurrence(owner)
  assert_true(
    table_input_export_start(
      source,
      table_input_export_occurrence(presence_output_owner()),
    )
    is Err(ResultView(ForeignOccurrence)),
  )
  assert_true(
    bind_managed_table_input_occurrence(
      presence_output_owner(),
      managed_table_input_occurrence_declarations(occurrence),
      "material",
    )
    is Err(ForeignOwner),
  )
  assert_true(
    bind_managed_table_input_occurrence(
      owner,
      managed_table_input_occurrence_declarations(occurrence),
      "missing",
    )
    is Err(MissingInput),
  )
  for
    limits in [
      { ..result_view_limits(), max_fields: 1, },
      { ..result_view_limits(), max_workspace_entries: 3, },
    ] {
    assert_true(
      table_input_export_start(source, occurrence, limits~)
      is Err(ResultView(Limit)),
    )
  }
  let preparation = table_input_export_start(source, occurrence, limits={
    ..result_view_limits(),
    max_mapping_work: 3,
  }).unwrap()
  assert_true(
    advance_completed_table_input_relation_export(preparation, 100)
    is Err(ResultView(Limit)),
  )
  assert_eq(completed_table_input_export_preparation_work(preparation), 3)
  assert_true(
    finish_completed_table_input_relation_export_preparation(preparation)
    is Err(NotFinished),
  )
  assert_true(cancel_completed_table_input_relation_export(preparation))
  assert_false(cancel_completed_table_input_relation_export(preparation))
  assert_eq(preparation.columns.capacity(), 0)
  assert_eq(preparation.names.capacity(), 0)
  assert_true(completed_output_available(source))
  assert_true(
    advance_completed_table_input_relation_export(preparation, 1) is Err(Closed),
  )
  let another = table_input_export_start(source, occurrence).unwrap()
  let (receipt, _) = table_input_export_finish(another, 1)
  assert_false(
    completed_table_input_export_preparation_matches_receipt(
      preparation, receipt,
    ),
  )
}

///|
fn table_input_managed_fixture(
  owner : @lower.BoundPrepared,
  source : CompletedOutput,
  live : Ref[Bool],
) -> ManagedCompletedOutput[Int] raise {
  let values = prepare_managed_output_values(
    owner,
    Step(0),
    3,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(values, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 7, 46L, () => live.val))).unwrap()
  for row in 0..<completed_row_count(source) {
    append_completed_projection_managed_values(values, source, row).unwrap()
  }
  let material = retain_managed_output(
    retention,
    finish_managed_output_values(values).unwrap(),
  ).unwrap()
  let preparation = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["events_0"],
    10000,
    1000,
  ).unwrap()
  let port = prepare_managed_completion_port(
    managed_test_profile(),
    preparation,
    Step(0),
    1000,
    10000,
    (_ : Unit) => Some(material),
  ).unwrap()
  complete_managed_output(port, ()).unwrap()
}

///|
test "private Table capture bridge retains sparse managed rows without granting public Result authority" {
  for reference_free in [false, true] {
    let (owner, source) = table_input_source_fixture()
    let live = Ref(true)
    let output = table_input_managed_fixture(owner, source, live)
    if reference_free {
      output.material.receipt.reference_rows.clear()
    }
    let bridge = prepare_managed_publication_bridge(
      output,
      output.material,
      3,
      stream_value_limits(),
      1000,
      10000,
    ).unwrap()
    for wire in ["{\"id\":1,\"p\":7}", "{\"id\":2,\"p\":null}", "{\"id\":3}"] {
      append_managed_publication_bridge_wire(
        bridge,
        wire,
        retained_row_test_limits(),
      ).unwrap()
    }
    let completed = finish_managed_publication_bridge(bridge).unwrap()
    let occurrence = table_input_export_occurrence(owner)
    let preparation = table_input_export_start(completed, occurrence).unwrap()
    assert_true(
      managed_publication_bridge_matches_table_input_export(
        bridge, output, preparation, occurrence,
      ),
    )
    assert_false(
      managed_publication_bridge_matches_table_input_export(
        bridge,
        output,
        preparation,
        table_input_export_occurrence(owner),
      ),
    )
    let (receipt, text) = table_input_export_finish(preparation, 1)
    assert_eq(text, "[{\"id\":1,\"p\":7},{\"id\":2,\"p\":null},{\"id\":3}]")
    assert_true(
      completed_table_input_export_preparation_matches_receipt(
        preparation, receipt,
      ),
    )
    assert_true(completed_presence_cell(completed, 2, 1) is Ok(Absent))
    assert_true(completed_cell(completed, 2, 1) is None)
    // The existing dense decoder and public Result checker remain strict.
    assert_true(
      decode_retained_row(
        presence_test_schema(),
        "{\"id\":3}",
        retained_row_test_limits(),
      )
      is Err(InvalidShape),
    )
    assert_true(
      @results.check(
        @lower.pipeline(@lower.bound_preparation(owner)),
        input_cursor(
          "{\"public\":{\"from\":\"rows\",\"fields\":[\"id\",\"p\"]}}",
        ),
        {
          max_results: 10,
          max_work: 100000,
          max_nodes: 10000,
          max_text_bytes: 100000,
          max_depth: 100,
        },
      )
      is Err(_),
    )
    close_managed_publication_bridge(bridge)
    assert_false(completed_output_available(completed))
    assert_false(
      managed_publication_bridge_matches_table_input_export(
        bridge, output, preparation, occurrence,
      ),
    )
    assert_true(managed_completed_output_available(output))
    assert_true(completed_output_available(source))
  }
}

///|
test "private Table capture bridge rejects malformed rows and liveness loss without releasing input" {
  for wire in ["{\"p\":7}", "{\"id\":null}", "{\"id\":1,\"p\":\"7\"}"] {
    let (owner, source) = table_input_source_fixture()
    let output = table_input_managed_fixture(owner, source, Ref(true))
    let bridge = prepare_managed_publication_bridge(
      output,
      output.material,
      3,
      stream_value_limits(),
      1000,
      10000,
    ).unwrap()
    assert_true(
      append_managed_publication_bridge_wire(
        bridge,
        wire,
        retained_row_test_limits(),
      )
      is Err(Wire(_)),
    )
    assert_true(finish_managed_publication_bridge(bridge) is Err(Closed))
    close_managed_publication_bridge(bridge)
    assert_true(managed_completed_output_available(output))
  }
  let (owner, source) = table_input_source_fixture()
  let live = Ref(true)
  let output = table_input_managed_fixture(owner, source, live)
  let bridge = prepare_managed_publication_bridge(
    output,
    output.material,
    3,
    stream_value_limits(),
    1000,
    10000,
  ).unwrap()
  append_managed_publication_bridge_wire(
    bridge,
    "{\"id\":1,\"p\":7}",
    retained_row_test_limits(),
  ).unwrap()
  live.val = false
  assert_true(
    append_managed_publication_bridge_wire(
      bridge,
      "{\"id\":2,\"p\":null}",
      retained_row_test_limits(),
    )
    is Err(Closed),
  )
  assert_true(finish_managed_publication_bridge(bridge) is Err(Closed))
  close_managed_publication_bridge(bridge)
  assert_true(completed_output_available(source))
}

///|
test "private Table capture decoder retains exact reference authority for existing dense callers" {
  let owner = managed_reference_owner()
  let source = managed_reference_output(owner, Ref(true))
  let limits : ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 10000,
    max_depth: 10,
    max_work: 10000,
  }
  let wire_limits : RetainedRowDecodeLimits = {
    max_bytes: 8192,
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 8192,
  }
  for valid in [false, true] {
    let bridge = prepare_managed_publication_bridge(
      source,
      source.material,
      1,
      limits,
      1000,
      10000,
    ).unwrap()
    let wire = "{\"r\":" +
      (if valid {
        managed_reference_wire()
      } else {
        managed_reference_wire_with_identity(
          "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        )
      }) +
      "}"
    let appended = append_managed_publication_bridge_wire(
      bridge, wire, wire_limits,
    )
    if valid {
      appended.unwrap()
      let completed = finish_managed_publication_bridge(bridge).unwrap()
      guard completed_cell(completed, 0, 0)
        is Some(Captured(@admitted.Reference(reference))) else {
        fail("retained reference authority was lost")
      }
      assert_eq(
        @admitted.reference_identity_cid(reference),
        "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      )
    } else {
      assert_true(appended is Err(Wire(_)))
      assert_true(finish_managed_publication_bridge(bridge) is Err(Closed))
    }
    close_managed_publication_bridge(bridge)
    assert_true(managed_completed_output_available(source))
  }
}
