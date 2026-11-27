///|
test "observed Run row keeps canonical bytes while admitting large observation originals" {
  let record = journal_encoding_original()
  let raw = "éprefix\n\"\\😀" + "x".repeat(160000)
  assert_eq(
    client_run_journal_row_body(record, run_observation_originals=Some(raw)),
    Err(CapacityExceeded),
  )
  let emissions : Array[(Int, Int, Int)] = []
  let body = client_run_journal_row_body(
    record,
    run_observation_originals=Some(raw),
    before_construction=Some((bytes, nodes, depth) => {
      emissions.push((bytes, nodes, depth))
      Ok(())
    }),
  ).unwrap()
  assert_true(body.length() > 131072)
  assert_true(emissions.length() > 1)
  assert_true(emissions[0].0 < body.length())
  for extent in emissions {
    assert_eq((extent.1, extent.2), (32, 4))
  }
  assert_true(
    decode_client_run_journal_row_with_observation_originals(body)
    is Err(CustodyLost),
  )
  let stages : Array[ClientRunJournalConstruction] = []
  let restored = decode_client_run_journal_row_with_observation_originals(
    body,
    before_construction=Some(stage => {
      stages.push(stage)
      Ok(())
    }),
  ).unwrap()
  assert_eq(restored.2, Some(raw))
  assert_eq(stages.length(), 3)
  assert_true(stages[0] is RunJournalParse(bytes) && bytes == body.length())
  assert_true(
    stages[1] is RunJournalCanonical(bytes, units, nodes, depth) &&
    bytes == body.length() &&
    units == 2L * bytes.to_int64() &&
    nodes > 0 &&
    nodes <= 32 &&
    depth <= 4,
  )
  assert_true(
    stages[2] is RunJournalRetained(bytes, units, nodes, depth) &&
    bytes == body.length() &&
    units == 2L * bytes.to_int64() &&
    nodes > 0 &&
    depth <= 4,
  )
  assert_eq(
    client_run_journal_row_body(
      restored.0,
      run_observation_originals=restored.2,
      before_construction=Some((_, _, _) => Ok(())),
    ).unwrap(),
    body,
  )
  assert_true(
    decode_client_run_journal_row_with_retained_identity(
      body,
      record.request,
      record.definition,
      before_construction=Some(_ => Ok(())),
    )
    is Ok(_),
  )
}

///|
test "observed Run row construction refusal stops without a completed body" {
  let calls = Ref(0)
  let result = client_run_journal_row_body(
    journal_encoding_original(),
    run_observation_originals=Some("x".repeat(200000)),
    before_construction=Some((_, _, _) => {
      calls.val += 1
      if calls.val == 2 {
        Err(CapacityExceeded)
      } else {
        Ok(())
      }
    }),
  )
  assert_eq(result, Err(CapacityExceeded))
  assert_eq(calls.val, 2)
  let body = client_run_journal_row_body(journal_encoding_original()).unwrap()
  for refuse_canonical in [false, true] {
    let stages = Ref(0)
    assert_true(
      decode_client_run_journal_row_with_observation_originals(
        body,
        before_construction=Some(stage => {
          stages.val += 1
          match stage {
            RunJournalParse(_) if refuse_canonical => Ok(())
            _ => Err(CustodyLost)
          }
        }),
      )
      is Err(CustodyLost),
    )
    assert_eq(stages.val, if refuse_canonical { 2 } else { 1 })
  }
}

///|
test "observed Run row preserves legacy combined-field limits and canonical identity" {
  let record = journal_encoding_original()
  let legacy = client_run_journal_row_body(record).unwrap()
  assert_eq(
    client_run_journal_row_body(
      record,
      before_construction=Some((_, _, _) => Ok(())),
    ).unwrap(),
    legacy,
  )
  for field in ["checkpoint", "effect", "policy", "binding"] {
    let oversized = Some("x".repeat(131073))
    let candidate = match field {
      "checkpoint" => { ..record, checkpoint: oversized, }
      "effect" => { ..record, effect_material_originals: oversized, }
      "policy" => { ..record, publication_policy_originals: oversized, }
      _ => { ..record, publication_binding: oversized, }
    }
    assert_eq(
      client_run_journal_row_body(
        candidate,
        before_construction=Some((_, _, _) => Ok(())),
      ),
      Err(CapacityExceeded),
    )
  }
  assert_eq(
    client_run_journal_row_body(
      record,
      local_run_policy_originals=Some("x".repeat(8193)),
      before_construction=Some((_, _, _) => Ok(())),
    ),
    Err(CapacityExceeded),
  )
  let text = @utf8.decode(legacy)
  for
    candidate in [
      " " + text,
      text.replace(
        old="\"dispatch_reserved\":false",
        new="\"dispatch_reserved\":null",
      ),
      text.replace(
        old="\"physical_start_claimed\":false",
        new="\"physical_start_claimed\":true",
      ),
      text.replace(old="\"version\":", new="\"unknown\":null,\"version\":"),
    ] {
    assert_true(
      decode_client_run_journal_row_with_observation_originals(
        @utf8.encode(candidate),
        before_construction=Some(_ => Ok(())),
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "Run canonical comparison cannot emit past its funded original body" {
  let record = journal_encoding_original()
  let request = client_request_identity_record_wire(record.request).unwrap()
  let definition = @publication.publication_contract_json(record.definition)
  let raw = "x".repeat(160000)
  let body = client_run_journal_row_body(
    record,
    run_observation_originals=Some(raw),
    before_construction=Some((_, _, _) => Ok(())),
  ).unwrap()
  let mut largest = 0
  let compare = limit => {
    client_run_journal_row_body_from_wires(
      record,
      request,
      definition,
      run_observation_originals=Some(raw),
      comparison_bytes=Some(limit),
      before_construction=Some((bytes, _, _) => {
        largest = Int::max(largest, bytes)
        Ok(())
      }),
    )
  }
  assert_eq(compare(body.length()), Ok(body))
  assert_eq(largest, body.length())
  largest = 0
  assert_eq(compare(body.length() - 1), Err(CapacityExceeded))
  assert_true(largest <= body.length() - 1)
  assert_eq(compare(0), Err(CapacityExceeded))
}

///|
test "Run decoded output handoff occurs only after exact canonical acceptance" {
  let body = client_run_journal_row_body(journal_encoding_original()).unwrap()
  let text = @utf8.decode(body)
  for
    candidate in [
      @utf8.encode(" " + text),
      @utf8.encode(text.replace(old="false", new="null")),
    ] {
    let handed = Ref(0)
    assert_true(
      decode_client_run_journal_row_with_observation_originals(
        candidate,
        before_construction=Some(stage => {
          if stage is RunJournalRetained(_, _, _, _) {
            handed.val += 1
          }
          Ok(())
        }),
      )
      is Err(CustodyLost),
    )
    assert_eq(handed.val, 0)
  }
  let handed = Ref(0)
  assert_true(
    decode_client_run_journal_row_with_observation_originals(
      body,
      before_construction=Some(stage => {
        if stage is RunJournalRetained(_, _, _, _) {
          handed.val += 1
          return Err(CustodyLost)
        }
        Ok(())
      }),
    )
    is Err(CustodyLost),
  )
  assert_eq(handed.val, 1)
}

///|
test "required Run identity reuses only the exact request and Definition" {
  let original = journal_encoding_original()
  let body = client_run_journal_row_body(original).unwrap()
  let foreign = derive_client_request_identity(
    {
      program_definition_cid: original.request.program_definition_cid,
      parameter_values_cid: original.request.parameter_values_cid,
    },
    original.request.authority_scope_cid,
    "another-caller",
    original.request.caller_input_intent_cid,
  ).unwrap()
  let lower = Ref(false)
  let retained = decode_client_run_journal_row_with_retained_identity(
      body,
      original.request,
      original.definition,
      require_retained_identity=true,
      before_construction=Some(stage => {
        if stage is RunJournalCanonical(_, _, _, _) {
          let (_, borrowed) = client_run_journal_decode_construction(
            stage,
            require_retained_identity=true,
          ).unwrap()
          let (_, full) = client_run_journal_decode_construction(stage).unwrap()
          lower.val = borrowed < full
        }
        Ok(())
      }),
    ).unwrap().0
  assert_true(lower.val)
  assert_true(physical_equal(retained.request, original.request))
  assert_true(physical_equal(retained.definition, original.definition))
  assert_true(
    decode_client_run_journal_row_with_retained_identity(
      body,
      foreign,
      original.definition,
    )
    is Ok(_),
  )
  assert_true(
    decode_client_run_journal_row_with_retained_identity(
      body,
      foreign,
      original.definition,
      require_retained_identity=true,
    )
    is Err(CustodyLost),
  )
}

///|
test "measured Run journal emission preserves exact original bytes and refusal" {
  let record = {
    ..journal_encoding_original(),
    checkpoint: Some("{\"text\":\"é\\r\\n😀\"}"),
    publication_binding: Some("original-store"),
    effect_material_originals: Some("original\"text".repeat(300)),
  }
  let original = client_run_journal_row_body(record).unwrap()
  let measured : Array[Int] = []
  let issued = client_run_journal_row_body(
    record,
    measure_construction=true,
    before_construction=Some((bytes, _, _) => {
      measured.push(bytes)
      Ok(())
    }),
  ).unwrap()
  assert_eq(measured, [0, original.length()])
  assert_eq(issued, original)
  let admitted = original.length() - 1
  assert_eq(
    client_run_journal_row_body(
      record,
      measure_construction=true,
      before_construction=Some((bytes, _, _) => {
        if bytes <= admitted {
          Ok(())
        } else {
          Err(CapacityExceeded)
        }
      }),
    ),
    Err(CapacityExceeded),
  )
}
