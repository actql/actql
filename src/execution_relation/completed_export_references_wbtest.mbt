///|
fn reference_export_fixture(
  conditional : Bool,
  first_live : Ref[Bool],
  second_live : Ref[Bool],
) -> (CompletedOutput, Array[@admitted.Value], Array[String]) raise {
  let contract = select_checked_contract(
    "{\"type\":\"content_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
  )
  let id_contract = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_presence_fields(
    [
      (Unqualified("id"), id_contract, Required),
      (
        Unqualified("p"),
        contract,
        if conditional {
          Conditional
        } else {
          Required
        },
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let first = issued_content_value(contract, first_live)
  let second = issued_content_value(contract, second_live)
  let null = @admitted.admit(contract, input_cursor("null"), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 0,
  }).unwrap()
  let owner = presence_output_owner(schema~)
  let admitted = prepare_admitted_output(
    owner,
    Step(0),
    4,
    stream_value_limits(),
  ).unwrap()
  for row in 0..<4 {
    let id = @admitted.admit(id_contract, input_cursor((row + 1).to_string()), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 0,
    }).unwrap()
    let p = match row {
      0 => Some(first)
      1 => Some(null)
      2 => if conditional { None } else { Some(null) }
      _ => Some(second)
    }
    if conditional {
      append_admitted_output_presence(
        admitted,
        admit_relation_row(schema, [Some(id), p], stream_value_limits()).unwrap(),
      ).unwrap()
    } else {
      append_admitted_output(admitted, [id, p.unwrap()]).unwrap()
    }
  }
  let rows = finish_admitted_output(admitted).unwrap()
  let prepared = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["events_0"],
    10000,
    1000,
  ).unwrap()
  let source = complete_trusted_output(
    prepare_trusted_output_port(prepared, Step(0), 1000, 10000, (_ : Unit) => {
      Some(rows)
    }).unwrap(),
    (),
  ).unwrap()
  guard first.value is @admitted.Reference(reference) else {
    fail("issued content")
  }
  let wire = @admitted.reference_wire(reference)
  (
    source,
    [first.value, second.value],
    [
      "{\"id\":1,\"p\":" + wire + "}",
      "{\"id\":2,\"p\":null}",
      if conditional {
        "{\"id\":3}"
      } else {
        "{\"id\":3,\"p\":null}"
      },
      "{\"id\":4,\"p\":" + wire + "}",
    ],
  )
}

///|
fn reference_export_stream(source : CompletedOutput) -> CompletedOutputExport {
  prepare_completed_output_export(
    source,
    4,
    stream_value_limits(),
    row_wire_limits(),
    4096,
  ).unwrap()
}

///|
fn reference_export_finish(
  source : CompletedOutput,
) -> (CompletedOutputExportReceipt, String) {
  let stream = reference_export_stream(source)
  let text = StringBuilder()
  let mut done = false
  for _ in 0..<10000 {
    let progress = advance_completed_output_export(stream, 1, 256).unwrap()
    assert_true(progress.steps <= 1) catch {
      _ => abort("export quantum")
    }
    if progress.batch is Some(batch) {
      text.write_string(batch)
    }
    if progress.complete {
      done = true
      break
    }
  }
  assert_true(done) catch {
    _ => abort("bounded export finish")
  }
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  text.write_string(tail)
  assert_true(stream.references is None) catch {
    _ => abort("export custody transfer")
  }
  (receipt, text.to_string())
}

///|
test "completed Content identity projection keeps original occurrences and custody" {
  let (receipt, originals) = content_borrow_export_fixture(
    true,
    Ref(true),
    Ref(true),
  )
  let source = receipt.rows.source.unwrap()
  let references = receipt.rows.references.unwrap()
  guard originals[0] is @admitted.Reference(first) &&
    originals[1] is @admitted.Reference(second) else {
    fail("original Content identities")
  }
  // Equal semantic identities retain distinct original authority. This
  // projection preserves both occurrences; the protocol owner deduplicates.
  assert_false(@admitted.reference_same_issuer(first, second))
  assert_eq(
    completed_relation_export_content_reference_cids(receipt, 2, 100).unwrap(),
    [
      @admitted.reference_identity_cid(first),
      @admitted.reference_identity_cid(second),
    ],
  )
  assert_true(physical_equal(receipt.rows.source.unwrap(), source))
  assert_true(physical_equal(receipt.rows.references.unwrap(), references))
  assert_true(
    completed_relation_export_content_reference_cids(receipt, 1, 100)
    is Err(Wire(Encoding(@encode.OutputLimit))),
  )
  assert_true(
    completed_relation_export_content_reference_cids(receipt, 2, 1)
    is Err(Wire(OrderLimit)),
  )
  cancel_completed_relation_export_receipt(receipt)
  assert_true(
    completed_relation_export_content_reference_cids(receipt, 2, 100)
    is Err(Unavailable),
  )
}

///|
test "completed Content identity projection fences one original current callback" {
  let (source, _, _) = reference_export_fixture(false, Ref(true), Ref(true))
  let calls = Ref(0)
  let retiring : Ref[CompletedRelationExportReceipt?] = Ref(None)
  let restricted = restrict_completed_output(source, () => {
    calls.val += 1
    if retiring.val is Some(receipt) {
      cancel_completed_relation_export_receipt(receipt)
    }
    true
  })
  let receipt = content_borrow_export(restricted)
  calls.val = 0
  assert_eq(
    completed_relation_export_content_reference_cids(receipt, 2, 100)
    .unwrap()
    .length(),
    2,
  )
  assert_eq(calls.val, 1)
  retiring.val = Some(receipt)
  calls.val = 0
  assert_true(
    completed_relation_export_content_reference_cids(receipt, 2, 100)
    is Err(Unavailable),
  )
  assert_eq(calls.val, 1)
}

///|
test "completed Content identity projection reads nested cached references without reissuance" {
  let content = "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}"
  let contract = select_checked_contract(
    "{\"type\":\"array\",\"nullable\":false,\"items\":" +
    content +
    ",\"max_items\":2}",
  )
  let id_contract = @contract.primitive(NumberType, nullable=false)
  let schema = @schema.from_fields(
    [(Unqualified("id"), id_contract), (Unqualified("p"), contract)],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let seed = issued_content_value(select_checked_contract(content), Ref(true))
  guard seed.value is @admitted.Reference(reference) else {
    fail("Content fixture")
  }
  let wire = @admitted.reference_wire(reference)
  let callbacks = Ref(0)
  let nested = @admitted.admit_host(
    @admitted.bind_reference_issuer((_, candidate) => candidate == wire, _ => {
      callbacks.val += 1
      true
    }),
    contract,
    input_cursor("[" + wire + "," + wire + "]"),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 10000, },
    { max_bytes: 4096, max_nodes: 64, max_depth: 4, max_text_units: 4096, },
  ).unwrap()
  let owner = presence_output_owner(schema~)
  let admitted = prepare_admitted_output(
    owner,
    Step(0),
    1,
    stream_value_limits(),
  ).unwrap()
  let id = @admitted.admit(id_contract, input_cursor("1"), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 0,
  }).unwrap()
  append_admitted_output(admitted, [id, nested]).unwrap()
  let rows = finish_admitted_output(admitted).unwrap()
  let prepared = prepare_completion(
    registered_relation_contracts(),
    prepared_sequence(owner),
    ["events_0"],
    10000,
    1000,
  ).unwrap()
  let source = complete_trusted_output(
    prepare_trusted_output_port(prepared, Step(0), 1000, 10000, (_ : Unit) => {
      Some(rows)
    }).unwrap(),
    (),
  ).unwrap()
  let receipt = content_borrow_export(source)
  callbacks.val = 0
  let cid = @admitted.reference_identity_cid(reference)
  assert_eq(
    completed_relation_export_content_reference_cids(receipt, 2, 100).unwrap(),
    [cid, cid],
  )
  assert_eq(callbacks.val, 0)
}

///|
test "retained reference-free material retirement does not claim physical release" {
  let live = Ref(true)
  let (output, handle) = retained_fixture(capture_fixture(), live)
  let material = retained_output_material(handle)
  assert_true(material.references is None)
  assert_true(advance_retained_output_reference_reclamation(material, 1))
  assert_true(live.val)
  assert_true(completed_output_available(output))
  live.val = false
  assert_true(advance_retained_output_reference_reclamation(material, 1))
  assert_false(completed_output_available(output))
}

///|
test "retained reference conversion preserves exact row authority NULL and absence" {
  for conditional in [false, true] {
    let (source, originals, wires) = reference_export_fixture(
      conditional,
      Ref(true),
      Ref(true),
    )
    let (receipt, text) = reference_export_finish(source)
    assert_eq(text, "[" + wires.join(",") + "]")
    // Independently hashed literal fixture preimages with Node crypto. These
    // are row identities, not physical-layout or reference-issuer identities.
    let expected = if conditional {
      "sha256:93003489cbf03cd6f33f38ed9971d6753f3ad629eb4b1881f65fef5fe3ba9c20"
    } else {
      "sha256:1c33e48befdc54f91b01d50a94bb076e9b1649262befe7ae3935c96601820e3f"
    }
    assert_eq(output_stream_identity(receipt.content).0, expected)
    let file_live = Ref(true)
    let handle = retain_admitted_output_stream(receipt.content, (), () => {
      file_live.val
    })
    let material = retained_output_material(handle)
    let retained = bind_completed_output_export(receipt, material).unwrap()
    assert_true(retained.table is None)
    assert_true(receipt.references is None)
    cancel_completed_export_receipt(receipt)
    let authority = material.references.unwrap()
    assert_eq(authority.workspace.live, 14)
    assert_false(advance_retained_output_reference_reclamation(material, 64))
    let importing = prepare_completed_output_import(
      retained,
      4,
      stream_value_limits(),
      row_wire_limits(),
      4096,
    ).unwrap()
    for wire in wires {
      append_completed_output_import_wire(
        importing,
        wire,
        retained_row_test_limits(),
      ).unwrap()
    }
    let restored = finish_completed_output_import(importing).unwrap()
    for (row, original) in [(0, originals[0]), (3, originals[1])] {
      let actual = if conditional {
        guard completed_presence_cell(restored, row, 1) is Ok(Present(actual)) else {
          fail("restored opaque presence value")
        }
        actual
      } else {
        guard completed_cell(restored, row, 1) is Some(Captured(actual)) else {
          fail("restored opaque value")
        }
        actual
      }
      guard actual is @admitted.Reference(actual_reference) &&
        original is @admitted.Reference(original_reference) else {
        fail("restored reference")
      }
      assert_true(physical_equal(actual_reference, original_reference))
    }
    if conditional {
      assert_true(
        completed_presence_cell(restored, 1, 1) is Ok(Present(@admitted.Null)),
      )
      assert_true(completed_presence_cell(restored, 2, 1) is Ok(Absent))
    } else {
      assert_true(completed_cell(restored, 1, 1) is Some(Null))
      assert_true(completed_cell(restored, 2, 1) is Some(Null))
    }
    file_live.val = false
    for step in 0..<14 {
      assert_eq(
        advance_retained_output_reference_reclamation(material, 1),
        step == 13,
      )
    }
    assert_eq((authority.workspace.live, authority.rows.capacity()), (0, 0))
    assert_true(advance_retained_output_reference_reclamation(material, 1))
    assert_true(completed_output_available(restored))
  }
}

///|
test "current stored-input issuer cannot replace a live export reference inventory" {
  for conditional in [false, true] {
    let (source, originals, wires) = reference_export_fixture(
      conditional,
      Ref(true),
      Ref(true),
    )
    let (receipt, _) = reference_export_finish(source)
    let file_live = Ref(true)
    let handle = retain_admitted_output_stream(receipt.content, (), () => {
      file_live.val
    })
    let material = retained_output_material(handle)
    let retained = bind_completed_output_export(receipt, material).unwrap()
    let importing = prepare_completed_output_import(
      retained,
      4,
      stream_value_limits(),
      row_wire_limits(),
      4096,
    ).unwrap()
    guard originals[0] is @admitted.Reference(reference) else {
      fail("original Ref")
    }
    let issuer = @admitted.bind_reference_reissuer((_, _) => Some(reference))
    assert_true(
      append_completed_output_import_wire(
        importing,
        wires[0],
        retained_row_test_limits(),
        reference_issuer=issuer,
      )
      is Err(WireRow(InvalidShape)),
    )
    assert_true(finish_completed_output_import(importing) is Err(Closed))
    assert_true(completed_output_available(source))
    assert_true(completed_output_available(retained))
    assert_true(@admitted.reference_available(reference))
    cancel_completed_export_receipt(receipt)
    file_live.val = false
    assert_true(advance_retained_output_reference_reclamation(material, 64))
  }
}

///|
test "retained reference re-admission refuses revoked missing and foreign row authority" {
  for refusal in ["revoked", "missing", "foreign"] {
    let first_live = Ref(true)
    let (source, _, wires) = reference_export_fixture(
      true,
      first_live,
      Ref(true),
    )
    let (receipt, _) = reference_export_finish(source)
    let file_live = Ref(true)
    let material = retained_output_material(
      retain_admitted_output_stream(receipt.content, (), () => file_live.val),
    )
    let retained = bind_completed_output_export(receipt, material).unwrap()
    let authority = material.references.unwrap()
    let importing = prepare_completed_output_import(
      retained,
      4,
      stream_value_limits(),
      row_wire_limits(),
      4096,
      deferred_reclamation=true,
    ).unwrap()
    match refusal {
      "revoked" => first_live.val = false
      "missing" => material.references = None
      _ => ()
    }
    // The exact second row has no reference authority. Its id/content cannot
    // borrow the first row's handle just because the schema accepts ContentRef.
    let result = append_completed_output_import_wire(
      importing,
      wires[0],
      retained_row_test_limits(),
    )
    if refusal == "foreign" {
      result.unwrap()
      assert_true(
        append_completed_output_import_wire(
          importing,
          wires[0],
          retained_row_test_limits(),
        )
        is Err(_),
      )
    } else {
      assert_true(result is Err(_))
    }
    assert_true(finish_completed_output_import(importing) is Err(Closed))
    assert_true(advance_cancel_completed_output_import(importing, 64))
    material.references = Some(authority)
    file_live.val = false
    assert_true(advance_retained_output_reference_reclamation(material, 64))
  }
}

///|
test "cancelled retained reference export retires roots without revoking producer authority" {
  let (source, originals, _) = reference_export_fixture(
    true,
    Ref(true),
    Ref(true),
  )
  let stream = reference_export_stream(source)
  let references = stream.references.unwrap()
  for _ in 0..<10000 {
    advance_completed_output_export(stream, 1, 256).unwrap() |> ignore
    if references.rows.get(0) is Some(row) &&
      row.get(1) is Some(cell) &&
      !cell.is_empty() {
      break
    }
  }
  assert_eq(references.workspace.live, 4)
  cancel_completed_output_export(stream)
  assert_true(next_completed_output_export(stream) is Err(Closed))
  assert_false(advance_cancel_completed_output_export(stream, 1))
  assert_eq(references.workspace.live, 3)
  assert_true(advance_cancel_completed_output_export(stream, 3))
  assert_eq(references.rows.capacity(), 0)
  for original in originals {
    guard original is @admitted.Reference(reference) else {
      fail("producer reference")
    }
    assert_true(@admitted.reference_available(reference))
  }
  assert_true(completed_output_available(source))
}
