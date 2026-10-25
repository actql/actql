///|
// Authored byte vector: three whole JOIN rows in name order; no runtime-derived
// request, output rows, digest or sampled cardinality builds the expectation.
fn original_keyed_serialized_expected() -> String {
  [0, 1, 2]
  .map(row => {
    "{\"name\":\"" +
    ["a", "b", "c"][row] +
    "\",\"content\":" +
    original_keyed_child_content(if row == 1 { 1 } else { 0 }) +
    "}\n"
  })
  .join("")
}

///|
fn original_keyed_encode_whole(
  prepared : @publication_host.PreparedClientProgram,
  output : @execution.CompletedOutput,
  max_bytes : Int,
) -> (String, @publication.ContentByteCompletion?) raise {
  let barrier = @publication_host.prepare_client_serialization(
    prepared,
    0,
    7,
    max_work=10000,
  ).unwrap()
  let encoder = @publication_host.start_client_serialization_encoder(
    barrier,
    max_rows=3,
    max_bytes~,
    max_value_nodes=1000,
    max_value_depth=32,
    max_frames=100,
  ).unwrap()
  let input = @publication_host.bind_client_serialization_completed_input(
    barrier, output, encoder,
  ).unwrap()
  assert_eq(@publication_host.client_serialization_input_rows(input), 3)
  let bytes = StringBuilder()
  // Empty header is still an actual encoder phase, not assumed free work.
  let mut total = 0
  let mut header_ready = false
  for _ in 0..<1000 {
    match @publication.advance_content_bytes(encoder, 7) {
      ContentBytesContinue(piece, work=used) => {
        bytes.write_string(piece)
        total += used
      }
      ContentBytesReady(piece, work=used) => {
        bytes.write_string(piece)
        total += used
        header_ready = true
        break
      }
      _ => fail("unexpected keyed JSONL header failure")
    }
  }
  assert_true(header_ready)
  for row in 0..<3 {
    @publication_host.start_client_serialization_input_row(input, row).unwrap()
    let mut ready = false
    for _ in 0..<20000 {
      match @publication.advance_content_bytes(encoder, 7) {
        ContentBytesContinue(piece, work=used) => {
          assert_true(used > 0 && used <= 7)
          total += used
          bytes.write_string(piece)
        }
        ContentBytesReady(piece, work=used) => {
          total += used
          bytes.write_string(piece)
          ready = true
          break
        }
        ContentBytesFailed(issue, ..) => {
          // The original bounded nested-value writer reports its refusal as
          // ContentValueEncoding; the final framing byte reports ByteLimit.
          // Neither returns a completion or permits partial publication.
          let expected = if max_bytes == 4096 {
            @publication.ContentValueEncoding
          } else {
            @publication.ContentByteLimit
          }
          assert_true(max_bytes == 4469 || max_bytes == 4096)
          assert_eq(issue, expected)
          assert_true(
            @publication.finish_content_bytes(encoder) is Err(failed) &&
            failed == expected,
          )
          @publication.cancel_content_byte_encoder(encoder)
          return (bytes.to_string(), None)
        }
      }
    }
    assert_true(ready)
  }
  assert_true(total > 0)
  let completion = @publication.finish_content_bytes(encoder).unwrap()
  @publication.cancel_content_byte_encoder(encoder)
  (bytes.to_string(), Some(completion))
}

///|
fn original_keyed_version_serialize(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  prepared : @publication_host.PreparedClientProgram,
  keyed : @publication_host.ClientKeyedAcquisition,
  lookup : @publication_host.ClientOriginalKeyedPrefixLookup,
  left_prefix : ClientOriginalKeyedPrefixInput,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : @execution.ExecutionCapacity,
  ledger : @resources.Ledger,
) -> Unit raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let suffix = start_client_original_keyed_serialization_suffix(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    lookup,
    keyed,
    0,
    7,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    execution,
    measurement,
    workspace=Some(workspace),
  ).unwrap()
  let active = @resources.ledger_usage(ledger)
  assert_eq(active.attempts, before.attempts)
  assert_eq(active.reserved_attempts, before.reserved_attempts + 1)
  assert_eq(active.holdings, before.holdings)
  assert_eq(active.transferred_bytes, before.transferred_bytes)
  // The same exact Source/prefix/assembly/children cannot begin a second suffix.
  assert_true(
    start_client_original_keyed_serialization_suffix(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      lookup,
      keyed,
      0,
      7,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      execution,
      measurement,
    )
    is Err(Unavailable),
  )
  assert_eq(@resources.ledger_usage(ledger), active)
  assert_false(
    @publication_host.cleanup_client_original_keyed_prefix_lookup(lookup, 1).unwrap(),
  )
  assert_false(cleanup_client_original_keyed_prefix_input(left_prefix).unwrap())
  assert_eq(@resources.ledger_usage(ledger), active)
  let mut output : @execution.CompletedOutput? = None
  for _ in 0..<10000 {
    match advance_client_serialization_prefix(suffix, 1).unwrap() {
      @local.Complete(value, ..) => {
        output = Some(value)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original keyed JOIN/serialization suffix failed")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  for row in 0..<3 {
    assert_eq(
      @execution.completed_output_row_wire(output, row, 10000, 1000, 100).unwrap(),
      "{\"content\":" +
      original_keyed_child_content(if row == 1 { 1 } else { 0 }) +
      ",\"name\":\"" +
      ["a", "b", "c"][row] +
      "\"}",
    )
  }
  // Independent original 4096 rejection remains; 4470 is a different authored
  // test Program bound, NOT a shared limit/profile increase or fixture relabel.
  for max_bytes in [4096, 4469] {
    let (partial, completion) = original_keyed_encode_whole(
      prepared, output, max_bytes,
    )
    assert_true(completion is None)
    assert_true(@utf8.encode(partial).length() <= max_bytes)
    assert_eq(@resources.ledger_usage(ledger), active)
  }
  let (bytes, completion) = original_keyed_encode_whole(prepared, output, 4470)
  assert_eq(bytes, original_keyed_serialized_expected())
  let completion = completion.unwrap()
  assert_eq((completion.row_count, completion.size_bytes), (3, 4470))
  assert_eq(
    completion.content_cid,
    "sha256:825b743cf65a3b85fd1220c1bfd6ec9b5c07389479d26df31b32ab31ecb354cd",
  )
  assert_true(client_serialization_prefix_work(suffix).unwrap() > 0L)
  assert_true(cleanup_client_serialization_prefix(suffix).unwrap())
  assert_false(@resources.reservation_open(suffix.reservation))
  assert_eq(@resources.ledger_usage(ledger).held_bytes, before.held_bytes)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
}
