///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 1000, max_nodes: 100, max_depth: 20, },
      source_path="managed-record-storage.json",
    ).unwrap(),
    {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
fn checked(contract : @contract.Contract, text : String) -> @value.CheckedValue {
  @value.admit(contract, cursor(text), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
fn limits() -> Limits {
  {
    max_input_records: 10,
    max_records: 10,
    max_fields_per_record: 10,
    max_value_bytes: 1000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 100,
    max_value_depth: 10,
    max_contract_work: 1000,
    max_work: 1000,
    max_workspace_slots: 1000,
  }
}

///|
fn events(open? : Bool = false) -> @carrier.Carrier {
  let records = @carrier.rows(
    [
      (
        @schema.Unqualified("id"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
      (
        @schema.Unqualified("time"),
        Some(@contract.primitive(@contract.NumberType, nullable=false)),
      ),
      (
        @schema.Unqualified("payload"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
    ],
    field_set=if open { @carrier.Open } else { @carrier.Closed },
    max_fields=3,
    max_name_bytes=20,
  ).unwrap()
  @carrier.events(
    records,
    id=@schema.Unqualified("id"),
    time=@schema.Unqualified("time"),
  ).unwrap()
}

///|
fn relation() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("value"),
          Some(@contract.primitive(@contract.StringType, nullable=false)),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  )
}

///|
fn relation_record(
  value : String,
) -> Array[(@schema.FieldName, @value.CheckedValue)] {
  [
    (
      @schema.Unqualified("value"),
      checked(
        @contract.primitive(@contract.StringType, nullable=false),
        "\"" + value + "\"",
      ),
    ),
  ]
}

///|
fn event_record(
  id : String,
  time : Double,
  payload : String,
) -> Array[(@schema.FieldName, @value.CheckedValue)] {
  [
    (
      @schema.Unqualified("payload"),
      checked(
        @contract.primitive(@contract.StringType, nullable=false),
        "\"" + payload + "\"",
      ),
    ),
    (
      @schema.Unqualified("id"),
      checked(
        @contract.primitive(@contract.StringType, nullable=false),
        "\"" + id + "\"",
      ),
    ),
    (
      @schema.Unqualified("time"),
      checked(
        @contract.primitive(@contract.NumberType, nullable=false),
        time.to_string(),
      ),
    ),
  ]
}

///|
fn vectors() -> @carrier.Carrier {
  let vector = @contract.vector_contract(2, nullable=false).unwrap()
  let records = @carrier.rows(
    [
      (
        @schema.Unqualified("tenant"),
        Some(@contract.primitive(@contract.StringType, nullable=false)),
      ),
      (
        @schema.Unqualified("item"),
        Some(@contract.primitive(@contract.NumberType, nullable=false)),
      ),
      (@schema.Unqualified("embedding"), Some(vector)),
    ],
    field_set=@carrier.Closed,
    max_fields=3,
    max_name_bytes=20,
  ).unwrap()
  @carrier.vectors(
    records,
    ids=[@schema.Unqualified("tenant"), @schema.Unqualified("item")],
    components=@schema.Unqualified("embedding"),
    max_identity_fields=2,
  ).unwrap()
}

///|
fn vector_record(
  tenant : String,
  item : Double,
  components : String,
) -> Array[(@schema.FieldName, @value.CheckedValue)] {
  [
    (
      @schema.Unqualified("tenant"),
      checked(
        @contract.primitive(@contract.StringType, nullable=false),
        "\"" + tenant + "\"",
      ),
    ),
    (
      @schema.Unqualified("item"),
      checked(
        @contract.primitive(@contract.NumberType, nullable=false),
        item.to_string(),
      ),
    ),
    (
      @schema.Unqualified("embedding"),
      checked(@contract.vector_contract(2, nullable=false).unwrap(), components),
    ),
  ]
}

///|
test "event storage preserves typed fields and exact identity uniqueness" {
  let builder = prepare(events(), limits()).unwrap()
  append(builder, event_record("a", 1.0, "é")).unwrap()
  append(builder, event_record("b", 2.0, "z")).unwrap()
  let stored = finish(builder).unwrap()
  assert_eq(@carrier.kind(carrier(stored)), @carrier.EventsKind)
  assert_eq(record_count(stored), 2)
  assert_eq(input_record_count(stored), 2)
  assert_eq(identity_count(stored), 1)
  assert_eq(identity_name_at(stored, 0), Some("id"))
  assert_eq(record_field_count(stored, 0), Some(3))
  assert_true(record_field_at(stored, 0, 0) is Some(_))
  assert_true(measured_input_value_bytes(stored) > 0)
  assert_eq(measured_input_value_bytes(stored), retained_value_bytes(stored))

  let duplicate = prepare(events(), limits()).unwrap()
  append(duplicate, event_record("a", 1.0, "first")).unwrap()
  assert_true(
    append(duplicate, event_record("a", 2.0, "second"))
    is Err(DuplicateIdentity),
  )
  assert_true(finish(duplicate) is Err(Closed))
}

///|
test "relation record storage preserves duplicate rows without an identity" {
  let builder = prepare(relation(), limits()).unwrap()
  append(builder, relation_record("same")).unwrap()
  append(builder, relation_record("same")).unwrap()
  let stored = finish(builder).unwrap()
  assert_eq(@carrier.kind(carrier(stored)), @carrier.RelationKind)
  assert_eq(record_count(stored), 2)
  assert_eq(identity_count(stored), 0)
  assert_eq(record_field_count(stored, 0), Some(1))
  assert_eq(record_field_count(stored, 1), Some(1))
}

///|
test "open event storage retains admitted unknown fields" {
  let builder = prepare(events(open=true), limits()).unwrap()
  let fields = event_record("a", 1.0, "known")
  fields.push(
    (
      @schema.Unqualified("extra"),
      checked(
        @contract.primitive(@contract.BooleanType, nullable=false),
        "true",
      ),
    ),
  )
  append(builder, fields).unwrap()
  let stored = finish(builder).unwrap()
  assert_eq(record_field_count(stored, 0), Some(4))

  let missing = prepare(events(open=true), limits()).unwrap()
  assert_true(
    append(
      missing,
      event_record("a", 1.0, "known").filter(pair => {
        @schema.reference_name(pair.0) != "payload"
      }),
    )
    is Err(InvalidRecord),
  )
}

///|
test "vector storage preserves composite identities and dimensions" {
  let builder = prepare(vectors(), limits()).unwrap()
  append(builder, vector_record("a", 1.0, "[1,2]")).unwrap()
  append(builder, vector_record("a", 2.0, "[3,4]")).unwrap()
  let stored = finish(builder).unwrap()
  assert_eq(@carrier.kind(carrier(stored)), @carrier.VectorsKind)
  assert_eq(record_count(stored), 2)
  assert_eq(identity_count(stored), 2)
  assert_eq(identity_name_at(stored, 0), Some("tenant"))
  assert_eq(identity_name_at(stored, 1), Some("item"))

  let duplicate = prepare(vectors(), limits()).unwrap()
  append(duplicate, vector_record("a", 1.0, "[1,2]")).unwrap()
  assert_true(
    append(duplicate, vector_record("a", 1.0, "[3,4]"))
    is Err(DuplicateIdentity),
  )
}

///|
test "record storage enforces exact retention and workspace admission" {
  let measured = prepare(events(), limits()).unwrap()
  append(measured, event_record("a", 1.0, "é")).unwrap()
  let result = finish(measured).unwrap()
  let bytes = retained_value_bytes(result)
  let slots = retained_workspace_slots(result)

  let exact = prepare(events(), {
    ..limits(),
    max_total_value_bytes: bytes,
    max_retained_value_bytes: bytes,
    max_workspace_slots: slots,
  }).unwrap()
  append(exact, event_record("a", 1.0, "é")).unwrap()
  assert_true(finish(exact) is Ok(_))

  let byte_short = prepare(events(), {
    ..limits(),
    max_total_value_bytes: bytes - 1,
  }).unwrap()
  assert_true(
    append(byte_short, event_record("a", 1.0, "é")) is Err(ValueLimit),
  )

  let slot_short = prepare(events(), {
    ..limits(),
    max_workspace_slots: slots - 1,
  }).unwrap()
  assert_true(
    append(slot_short, event_record("a", 1.0, "é")) is Err(WorkspaceLimit),
  )
}

///|
fn assert_failed_builder_reclaims(builder : Builder) -> Unit raise {
  let measured = builder_measured_input_value_bytes(builder)
  let work = builder_construction_work(builder)
  assert_eq(builder_record_count(builder), 1)
  assert_true(builder_retained_value_bytes(builder) > 0)
  assert_true(builder_workspace_slots(builder) > 0)
  assert_true(cancel(builder))
  assert_eq(builder_record_count(builder), 0)
  assert_eq(builder_retained_value_bytes(builder), 0)
  assert_eq(builder_workspace_slots(builder), 0)
  assert_eq(builder_measured_input_value_bytes(builder), measured)
  assert_eq(builder_construction_work(builder), work)
  assert_false(cancel(builder))
  assert_true(
    append(builder, event_record("later", 3.0, "closed")) is Err(Closed),
  )
  assert_true(finish(builder) is Err(Closed))
}

///|
test "failed record builders retain cleanup custody without refunding work" {
  let baseline = prepare(events(), limits()).unwrap()
  append(baseline, event_record("a", 1.0, "first")).unwrap()
  let measured = finish(baseline).unwrap()
  let bytes = measured_input_value_bytes(measured)
  let work = construction_work(measured)
  let slots = retained_workspace_slots(measured)

  let duplicate = prepare(events(), limits()).unwrap()
  append(duplicate, event_record("a", 1.0, "first")).unwrap()
  assert_true(
    append(duplicate, event_record("a", 2.0, "second"))
    is Err(DuplicateIdentity),
  )
  assert_failed_builder_reclaims(duplicate)

  let malformed = prepare(events(), limits()).unwrap()
  append(malformed, event_record("a", 1.0, "first")).unwrap()
  assert_true(
    append(
      malformed,
      event_record("b", 2.0, "second").filter(pair => {
        @schema.reference_name(pair.0) != "payload"
      }),
    )
    is Err(InvalidRecord),
  )
  assert_failed_builder_reclaims(malformed)

  let record_limited = prepare(events(), { ..limits(), max_records: 1, }).unwrap()
  append(record_limited, event_record("a", 1.0, "first")).unwrap()
  assert_true(
    append(record_limited, event_record("b", 2.0, "second")) is Err(RecordLimit),
  )
  assert_failed_builder_reclaims(record_limited)

  let value_limited = prepare(events(), {
    ..limits(),
    max_total_value_bytes: bytes,
  }).unwrap()
  append(value_limited, event_record("a", 1.0, "first")).unwrap()
  assert_true(
    append(value_limited, event_record("b", 2.0, "second")) is Err(ValueLimit),
  )
  assert_failed_builder_reclaims(value_limited)

  let work_limited = prepare(events(), { ..limits(), max_work: work, }).unwrap()
  append(work_limited, event_record("a", 1.0, "first")).unwrap()
  assert_true(
    append(work_limited, event_record("b", 2.0, "second")) is Err(WorkLimit),
  )
  assert_failed_builder_reclaims(work_limited)

  let workspace_limited = prepare(events(), {
    ..limits(),
    max_workspace_slots: slots,
  }).unwrap()
  append(workspace_limited, event_record("a", 1.0, "first")).unwrap()
  assert_true(
    append(workspace_limited, event_record("b", 2.0, "second"))
    is Err(WorkspaceLimit),
  )
  assert_failed_builder_reclaims(workspace_limited)
}
