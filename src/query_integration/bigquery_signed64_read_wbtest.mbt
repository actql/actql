///|
fn bigquery_signed64_fields() -> Array[Json] {
  let fields = bigquery_fields()
  fields[1] = Json::object(
    Map([
      ("name", "ACTIVE_USERS".to_json()),
      ("type", "INT64".to_json()),
      ("mode", "REQUIRED".to_json()),
    ]),
  )
  fields
}

///|
fn bigquery_signed64_preparation() -> @bigquery_read.PreparedRead raise {
  bigquery_read_preparation(
    description=Some(
      bigquery_read_description(fields=Some(bigquery_signed64_fields())),
    ),
  ).unwrap() catch {
    @program_check.LocalConstructionFailure::Source(cause) =>
      match cause {
        Requests(_) => fail("BigQuery Signed64 source request admission")
        RequestForm(_) => fail("BigQuery Signed64 request form")
        Checks(_) => fail("BigQuery Signed64 checked source")
        Identity(_) => fail("BigQuery Signed64 original identity")
        Declarations(_) => fail("BigQuery Signed64 declaration")
        Registration(_) => fail("BigQuery Signed64 registration")
        SourceView(Program(Program(Pipeline(stage, issue)))) =>
          fail(
            "BigQuery Signed64 pipeline " +
            stage.to_string() +
            ": " +
            @debug.to_string(issue.kind),
          )
        SourceView(Program(Registration(stage, issue))) =>
          fail(
            "BigQuery Signed64 registration " +
            stage.to_string() +
            ": " +
            @debug.to_string(issue),
          )
        SourceView(Program(Program(issue))) =>
          match issue {
            LocalInput(_, _) => fail("BigQuery Signed64 Program LocalInput")
            Import(_, _) => fail("BigQuery Signed64 Program Import")
            Results(_, _) => fail("BigQuery Signed64 Program Results")
            Order(stage, PipelineOrder(issue)) =>
              fail(
                "BigQuery Signed64 order pipeline " +
                stage.to_string() +
                ": " +
                @debug.to_string(issue.kind),
              )
            Order(stage, ProducerOrder(issue)) =>
              fail(
                "BigQuery Signed64 producer order " +
                stage.to_string() +
                ": " +
                @debug.to_string(issue.issue.kind),
              )
            Order(stage, ResultOrder(issue)) =>
              fail(
                "BigQuery Signed64 result order " +
                stage.to_string() +
                ": " +
                @debug.to_string(issue.kind),
              )
            Ports(_, _) => fail("BigQuery Signed64 Program Ports")
            TableInputs(_, _) => fail("BigQuery Signed64 Program TableInputs")
            Wiring(_) => fail("BigQuery Signed64 Program Wiring")
            _ => fail("BigQuery Signed64 Program registration or limits")
          }
        SourceView(Program(ForeignSource)) =>
          fail("BigQuery Signed64 foreign Source")
        SourceView(Program(ForeignPartition(stage))) =>
          fail("BigQuery Signed64 foreign partition " + stage.to_string())
        SourceView(Program(BudgetExceeded)) =>
          fail("BigQuery Signed64 Program budget")
        SourceView(Program(_)) =>
          fail("BigQuery Signed64 Source view environment or calendar")
        SourceView(Binding(_)) => fail("BigQuery Signed64 Source view Binding")
        SourceView(Context(_)) => fail("BigQuery Signed64 Source view Context")
        SourceView(_) => fail("BigQuery Signed64 Source view limits")
        _ => fail("BigQuery Signed64 source capacity or declaration inventory")
      }
    other => raise other
  }
}

///|
test "BigQuery Signed64 crosses original checked Source RowRun and capture without rounding" {
  let fields = bigquery_signed64_fields()
  let prepared = bigquery_signed64_preparation()
  let body = bigquery_body(
    [
      bigquery_row("a1", "-9223372036854775808", "down".to_json()),
      bigquery_row("a2", "9223372036854775807", Json::null()),
    ],
    schema_fields=Some(fields),
  )
  let transfer = body.length().to_int64()
  let ledger = bigquery_read_ledger(prepared, transfer)
  guard @bigquery_read.start_accounted_read(
      prepared,
      bigquery_job(),
      "bq-signed64-capture",
      _ => true,
      ledger,
      transfer,
      4096L,
      bigquery_read_limits(),
      1,
    )
    is Ok(read) else {
    fail("BigQuery Signed64 original accounted read was refused")
  }
  assert_eq(
    bigquery_expect(@bigquery_read.accept_query_page(read, None, body)),
    2,
  )
  @bigquery_read.finish_result_read(read).unwrap()
  let capture = @bigquery_read.capture_result_read(read).unwrap()
  let storage = @query.captured_source_storage(
    @row_host.row_capture_source(capture).unwrap(),
    10000,
    10000,
  ).unwrap()
  assert_true(
    @execution.producer_storage_cell(storage, 0, 1)
    is Some(@execution.Captured(@admitted.Signed64(-9223372036854775808L))),
  )
  assert_true(
    @execution.producer_storage_cell(storage, 1, 1)
    is Some(@execution.Captured(@admitted.Signed64(9223372036854775807L))),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, transfer)
  bigquery_assert_retired(read, ledger)
  assert_false(@execution.producer_storage_available(storage))
}

///|
test "BigQuery Signed64 overflow consumes the original page charge without partial Source" {
  let fields = bigquery_signed64_fields()
  let prepared = bigquery_signed64_preparation()
  let body = bigquery_body(
    [
      bigquery_row("a1", "9007199254740993", "down".to_json()),
      bigquery_row("a2", "9223372036854775808", Json::null()),
    ],
    schema_fields=Some(fields),
  )
  let transfer = body.length().to_int64()
  let ledger = bigquery_read_ledger(prepared, transfer)
  let stopped = Ref(false)
  guard @bigquery_read.start_accounted_read(
      prepared,
      bigquery_job(),
      "bq-signed64-overflow",
      _ => stopped.val,
      ledger,
      transfer,
      4096L,
      bigquery_read_limits(),
      1,
    )
    is Ok(read) else {
    fail("BigQuery Signed64 original accounted read was refused")
  }
  assert_true(@bigquery_read.accept_query_page(read, None, body) is Err(_))
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, transfer)
  assert_true(@bigquery_read.capture_result_read(read) is Err(_))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @bigquery_read.close_result_read(read)
    is Err(@bigquery_read.TransportUnsettled),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@bigquery_read.result_read_job(read) is Some(_))
  stopped.val = true
  bigquery_assert_retired(read, ledger)
}
