///|
/// Conformance setup only. Actual capture stays opaque in the same process;
/// the transport asks the shared adapter for one parameter at a time.
struct OwnedFixedFixture {
  compute : @duckdb.FixedCompute
  local_binding : @connector.PreparedCompute[@execution.GeneratedSequence]
  local_choice : @connector.FixedComputeChoice
  configuration : @duckdb_driver.ComputeHostConfiguration
  consumer : @execution.GeneratedSequence
  measurement : @execution.FixedProducerMeasurement
  mut measured : @execution.FixedProducerMeasuredOutput?
  mut demand : @duckdb.FixedComputeDemand?
  mut receiving : @duckdb.FixedComputeReceiving?
  mut receipt : @duckdb.FixedComputeReceipt?
}

///|
#export_name("ownedFixedCreate")
pub fn owned_fixed_create(
  producer : IssuedNativeFixture,
  output : @execution.CompletedOutput,
  registry_json : String,
  values_json : String,
  fragment_json : String,
) -> OwnedFixedFixture {
  owned_fixed_from_output(
    @duckdb.native_query_owner(@duckdb.native_scan_query(producer.scan)),
    output,
    registry_json,
    values_json,
    fragment_json,
  )
}

///|
fn owned_fixed_from_output(
  owner : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  projection? : String = "id",
  predicate? : String = "id > 2",
  count? : Bool = false,
  keyed_count? : Bool = false,
  inner_join? : Bool = false,
) -> OwnedFixedFixture {
  try {
    let receiver = if inner_join {
      issued_fixture_join_consumer(owner, field=projection)
    } else {
      issued_fixture_consumer(
        owner,
        steps=if keyed_count {
          "[{\"group\":{\"by\":[\"amount\"],\"aggregates\":{\"n\":{\"fn\":\"count\"},\"p\":{\"fn\":\"count\",\"field\":\"amount\"}}}}]"
        } else if count {
          "[{\"group\":{\"by\":[],\"aggregates\":{\"id\":{\"fn\":\"count\"}}}}]"
        } else {
          "[{\"filter\":\"" +
          predicate +
          "\"},{\"select\":[\"" +
          projection +
          "\"]}]"
        },
      )
    }
    let inputs = Array::makei(if inner_join { 2 } else { 1 }, index => {
      let bound = @execution.bind_completed_input(
        receiver, index, owner, output,
      ).unwrap()
      @execution.prepare_producer_read(receiver, bound, 100, 10000).unwrap()
    })
    let request = @connector.prepare_fixed_compute_request(inputs, {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    }).unwrap()
    let registry = @connector.prepare_capability_registry(
      [
        { name: "local", acquisition: false, fixed_compute: true, },
        { name: "duckdb", acquisition: true, fixed_compute: true, },
      ],
      2,
      11,
    ).unwrap()
    let quantities : @connector.QueryQuantities = {
      transfer_bytes: None,
      retained_bytes: None,
      money_units: None,
    }
    let local_binding = @local_connector.local_fixed_compute_candidate(
      @connector.capability_registration_at(registry, 0).unwrap(),
      request,
      fixture_generated(
        receiver,
        registry_json,
        values_json,
        fragment_json,
        !count && !inner_join,
      ),
      [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(20L), }],
      quantities,
      100,
    ).unwrap()
    let compilation : @duckdb.NativeQueryLimits = {
      max_entries: 100,
      max_sql_bytes: 10000,
      expressions: {
        max_nodes: 1000,
        max_work: 10000,
        max_depth: 100,
        max_literal_nodes: 1000,
        max_literal_text_bytes: 10000,
      },
    }
    let native = if inner_join {
      let query = @duckdb.compile_fixed_inner_join(
        receiver,
        "main",
        ["owned_left", "owned_right"],
        compilation,
      ).unwrap()
      let imported = @duckdb.prepare_fixed_join_inputs(
        query,
        inputs,
        { max_rows: 100, max_work: 100000, max_entries: 10000, },
        100,
        10000,
      ).unwrap()
      @duckdb_compute.duckdb_bound_compute_candidate(
        @connector.capability_registration_at(registry, 1).unwrap(),
        request,
        @duckdb.prepare_fixed_join_compute(imported, 100).unwrap(),
        [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
        quantities,
        100,
      ).unwrap()
    } else {
      @duckdb_compute.duckdb_fixed_compute_candidate(
        @connector.capability_registration_at(registry, 1).unwrap(),
        request,
        "owned_input",
        compilation,
        [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
        quantities,
        100,
      ).unwrap()
    }
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [
          @connector.prepared_compute_candidate(local_binding),
          @connector.prepared_compute_candidate(native),
        ],
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("fixed candidate choice")
    }
    guard @connector.choose_fixed_compute_candidate(
        registry,
        request,
        [@connector.prepared_compute_candidate(local_binding)],
        None,
        100,
      ).unwrap()
      is Proposed(local_choice) else {
      abort("local reference choice")
    }
    {
      compute: @connector.fixed_compute_choice_payload(choice, native).unwrap(),
      local_binding,
      local_choice,
      configuration: @duckdb_driver.configure_compute_host(
        choice,
        native,
        @execution.generated_completion_preparation(
          @connector.fixed_compute_choice_payload(local_choice, local_binding).unwrap(),
        ),
        {
          values: issued_native_measure_limits(),
          demand: issued_native_measure_limits(),
          physical: {
            max_rows: 100,
            max_cells: 1000,
            max_nodes: 1000,
            max_text_bytes: 10000,
          },
          retention: {
            max_nodes: 10000,
            max_text_bytes: 10000,
            max_depth: 100,
            max_work: 100000,
          },
          metadata_work: 10000,
          completion_entries: 100,
          completion_name_bytes: 10000,
        },
        {
          max_bytes: 100000,
          max_nodes: 10000,
          max_columns: 10,
          max_rows: 100,
          max_text_bytes: 100000,
        },
      ),
      consumer: fixture_generated(
        issued_fixture_consumer(
          receiver,
          steps=if keyed_count {
            "[{\"select\":[\"amount\",\"n\",\"p\"]}]"
          } else {
            "[{\"select\":[\"" + projection + "\"]}]"
          },
          target=@duckdb.fixed_query_target(
            @duckdb.fixed_compute_query(
              @connector.fixed_compute_choice_payload(choice, native).unwrap(),
            ),
          ),
        ),
        registry_json,
        values_json,
        fragment_json,
        false,
      ),
      measurement: @execution.prepare_streamed_fixed_producer_measurement(
        inputs,
        if count || keyed_count || inner_join {
          @pipeline.Step(0)
        } else {
          @pipeline.Step(1)
        },
        max_rows=100,
        max_value_bytes=10000,
        issued_native_measure_limits(),
      ).unwrap(),
      measured: None,
      demand: None,
      receiving: None,
      receipt: None,
    }
  } catch {
    _ => abort("owned fixed conformance setup")
  }
}

///|
#export_name("ownedFixedNext")
pub fn owned_fixed_next(
  previous : OwnedFixedFixture,
  output : @execution.CompletedOutput,
  registry_json : String,
  values_json : String,
  fragment_json : String,
) -> OwnedFixedFixture {
  owned_fixed_from_output(
    @duckdb.fixed_query_owner(@duckdb.fixed_compute_query(previous.compute)),
    output,
    registry_json,
    values_json,
    fragment_json,
  )
}

///|
#export_name("ownedCountCreate")
pub fn owned_count_create(
  producer : IssuedNativeFixture,
  output : @execution.CompletedOutput,
  registry_json : String,
  values_json : String,
  fragment_json : String,
) -> OwnedFixedFixture {
  owned_fixed_from_output(
    @duckdb.native_query_owner(@duckdb.native_scan_query(producer.scan)),
    output,
    registry_json,
    values_json,
    fragment_json,
    count=true,
  )
}

///|
#export_name("ownedFixedConfiguration")
pub fn owned_fixed_configuration(
  value : OwnedFixedFixture,
) -> @duckdb_driver.ComputeHostConfiguration {
  value.configuration
}

///|
#export_name("ownedJoinCreate")
pub fn owned_join_create(
  producer : IssuedNativeFixture,
  output : @execution.CompletedOutput,
  registry_json : String,
  values_json : String,
  fragment_json : String,
) -> OwnedFixedFixture {
  owned_fixed_from_output(
    @duckdb.native_query_owner(@duckdb.native_scan_query(producer.scan)),
    output,
    registry_json,
    values_json,
    fragment_json,
    inner_join=true,
  )
}

///|
fn issued_fixture_join_consumer(
  owner : @lower.BoundPrepared,
  field? : String = "id",
) -> @lower.BoundPrepared {
  let source = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(1),
  ).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    cursor(
      "[{\"from\":\"l\",\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"" +
      field +
      "\",\"right\":\"" +
      field +
      "\"}],\"select\":{\"" +
      field +
      "\":\"left." +
      field +
      "\"}}}]",
    ),
    [
      ("l", @pipeline.ProducedInput(source)),
      ("r", @pipeline.ProducedInput(source)),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
#export_name("ownedFixedRetainedInput")
pub fn owned_fixed_retained_input(
  value : OwnedFixedFixture,
  output : @execution.CompletedOutput,
) -> @execution.ProducerRead? {
  let owner = @duckdb.fixed_query_owner(
    @duckdb.fixed_compute_query(value.compute),
  )
  let receiver = @execution.generated_sequence_owner(value.consumer)
  guard @execution.bind_completed_input(receiver, 0, owner, output) is Ok(bound) else {
    return None
  }
  match @execution.prepare_producer_read(receiver, bound, 100, 10000) {
    Ok(input) => Some(input)
    Err(_) => None
  }
}

///|
#export_name("ownedFixedManagedInput")
pub fn owned_fixed_managed_input(
  value : OwnedFixedFixture,
  output : @execution.ManagedCompletedOutput[Int],
) -> @execution.ManagedProducerRead[Int]? {
  @execution.prepare_managed_producer_read(
    @execution.generated_sequence_owner(value.consumer),
    0,
    @duckdb.fixed_query_owner(@duckdb.fixed_compute_query(value.compute)),
    output,
    100,
    10000,
  ).to_option()
}

///|
#export_name("ownedFixedManagedInputUsage")
pub fn owned_fixed_managed_input_usage(
  value : OwnedFixedFixture,
  input : @execution.ManagedProducerRead[Int],
) -> Array[Int] {
  let owner = @execution.generated_sequence_owner(value.consumer)
  let measurement = @execution.prepare_reused_managed_producer_measurement(
    [input],
    Step(@lower.node_count(@lower.bound_preparation(owner)) - 1),
    max_rows=100,
    max_value_bytes=10000,
    { max_work: 10000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    10000,
  ).unwrap()
  let (work, bytes, nodes) = @execution.managed_producer_measurement_usage(
    measurement,
  )
  [@execution.managed_producer_read_row_count(input), work, bytes, nodes]
}

///|
/// Conditional metadata only; this helper does not issue an executed take.
#export_name("managedSelectedTextMeasurements")
pub fn managed_selected_text_measurements(
  value : OwnedFixedFixture,
  output : @execution.ManagedCompletedOutput[Int],
  rows : Array[Int],
) -> Array[Int] raise {
  assert_true(
    rows.length() <= @execution.managed_completed_output_row_count(output),
  )
  let owner = @duckdb.fixed_query_owner(
    @duckdb.fixed_compute_query(value.compute),
  )
  let receiver = issued_fixture_consumer(
    owner,
    steps="[{\"take\":2},{\"select\":[\"amount\"]}]",
    target=@duckdb.fixed_query_target(
      @duckdb.fixed_compute_query(value.compute),
    ),
  )
  let input = @execution.prepare_managed_producer_read(
    receiver, 0, owner, output, 100, 10000,
  ).unwrap()
  let expressions : @lower.ExpressionLimits = {
    max_nodes: 100,
    max_work: 1000,
    max_depth: 100,
    max_literal_nodes: 100,
    max_literal_text_bytes: 1000,
  }
  let kernels = Array::makei(2, i => {
    @lower.prepare_kernel(
      receiver,
      i,
      max_bindings=100,
      max_name_bytes=1000,
      expressions,
    ).unwrap()
  })
  let plan = @execution.prepare_managed_view_plan(
    input, kernels, 1000, 10000, 100,
  ).unwrap()
  let facts = @execution.managed_view_selection_measurements(plan, rows, 1000).unwrap()[0].unwrap()
  [facts.rows, facts.bytes, facts.nodes, facts.max_value_bytes, facts.null_rows]
}

///|
#export_name("ownedFixedManagedCountInput")
pub fn owned_fixed_managed_count_input(
  value : OwnedFixedFixture,
  output : @execution.ManagedCompletedOutput[Int],
) -> @execution.ManagedProducerRead[Int] {
  let query = @duckdb.fixed_compute_query(value.compute)
  let owner = @duckdb.fixed_query_owner(query)
  let receiver = issued_fixture_consumer(
    owner,
    steps="[{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
    target=@duckdb.fixed_query_target(query),
  )
  @execution.prepare_managed_producer_read(
    receiver, 0, owner, output, 100, 10000,
  ).unwrap()
}

///|
#export_name("managedFixedQuery")
pub fn managed_fixed_query(
  input : @execution.ManagedProducerRead[Int],
) -> @duckdb.ManagedFixedQuery[Int] {
  @duckdb.prepare_managed_fixed_query(input, "managed_input", {
    max_entries: 100,
    max_sql_bytes: 10000,
    expressions: {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
}

///|
#export_name("ownedFixedManagedFilterInput")
pub fn owned_fixed_managed_filter_input(
  query : @duckdb.ManagedFixedQuery[Int],
  output : @execution.ManagedCompletedOutput[Int],
) -> @execution.ManagedProducerRead[Int] {
  let native = @duckdb.managed_fixed_query_query(query)
  let owner = @duckdb.fixed_query_owner(native)
  let receiver = issued_fixture_consumer(
    owner,
    steps="[{\"filter\":\"n > 1\"},{\"select\":[\"n\"]}]",
    target=@duckdb.fixed_query_target(native),
  )
  @execution.prepare_managed_producer_read(
    receiver, 0, owner, output, 100, 10000,
  ).unwrap()
}

///|
#export_name("managedFixedQueryParameter")
pub fn managed_fixed_query_parameter(
  query : @duckdb.ManagedFixedQuery[Int],
) -> String raise {
  let parameter = @duckdb.fixed_query_parameter(
    @duckdb.managed_fixed_query_query(query),
    0,
  ).unwrap()
  let writer = @encode.writer(10000, 100, 10)
  @duckdb.emit_physical_parameter(parameter, writer)
  @encode.finish(writer)
}

///|
#export_name("managedColumnMeasurement")
pub fn managed_column_measurement(
  input : @execution.ManagedProducerRead[Int],
) -> Array[Int] {
  let facts = @execution.managed_producer_read_column_measurement(input, 0).unwrap()
  [facts.rows, facts.bytes, facts.nodes, facts.max_value_bytes, facts.null_rows]
}

///|
#export_name("managedFixedViewPlan")
pub fn managed_fixed_view_plan(
  query : @duckdb.ManagedFixedQuery[Int],
) -> @execution.ManagedViewPlan[Int] raise {
  assert_true(@duckdb.managed_fixed_query_query(query) is FilterSelect(_))
  @duckdb.prepare_managed_fixed_view_plan(query, {
    max_entries: 100,
    max_sql_bytes: 10000,
    expressions: {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
}

///|
/// Fixture issuer restricted to selecting zero/one rows from one admitted
/// scalar count. Real native execution and sealed-output binding are checked
/// by the Node test Host; no arbitrary subset totals are inferred here.
#export_name("managedSingleRowSelectionFacts")
pub fn managed_single_row_selection_facts(
  input : @execution.ManagedProducerRead[Int],
  rows : Int,
) -> @execution.ManagedViewOutputFacts raise {
  let column = @execution.managed_producer_read_column_measurement(input, 0).unwrap()
  assert_eq(column.rows, 1)
  assert_true(rows == 0 || rows == 1)
  {
    rows,
    columns: [
      if rows == 1 {
        column
      } else {
        {
          ..column,
          rows: 0,
          bytes: 0,
          nodes: 0,
          max_value_bytes: 0,
          null_rows: 0,
        }
      },
    ],
    admission_usage: { work: 0, nodes: 0, text_bytes: 0, },
  }
}

///|
#export_name("managedFixedQueryMatches")
pub fn managed_fixed_query_matches(
  query : @duckdb.ManagedFixedQuery[Int],
  input : @execution.ManagedProducerRead[Int],
) -> Bool {
  @duckdb.managed_fixed_query_matches(query, input)
}

///|
#export_name("managedFixedQuerySql")
pub fn managed_fixed_query_sql(
  query : @duckdb.ManagedFixedQuery[Int],
) -> Array[String] {
  [
    @duckdb.managed_fixed_query_create_sql(query),
    @duckdb.fixed_query_sql(@duckdb.managed_fixed_query_query(query)),
  ]
}

///|
#export_name("managedQueryCompletion")
pub fn managed_query_completion(
  query : @duckdb.ManagedFixedQuery[Int],
  profile : @execution.ManagedExecutionProfile,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  max_value_bytes : Int,
  authorize : () -> Bool,
  transport : (@execution.ManagedOutputValueReceipt) -> Bool,
) -> @duckdb_compute.ManagedInputDuckDBCompletion[Int] raise {
  let generated = fixture_generated(
    @duckdb.fixed_query_owner(@duckdb.managed_fixed_query_query(query)),
    registry_json,
    values_json,
    fragment_json,
    @duckdb.managed_fixed_query_query(query) is FilterSelect(_),
  )
  @duckdb_compute.prepare_managed_input_duckdb_completion(
    query,
    @execution.generated_completion_preparation(generated),
    profile,
    {
      values: {
        max_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
      demand: {
        max_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
      physical: managed_file_physical_limits(),
      retention: {
        max_work: 10000,
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 100,
      },
      metadata_work: 10000,
      completion_entries: 1000,
      completion_name_bytes: 10000,
    },
    100,
    max_value_bytes,
    authorize,
    transport,
  ).unwrap()
}

///|
#export_name("managedCountRead")
pub fn managed_count_read(
  query : @duckdb.ManagedFixedQuery[Int],
  output : @execution.ManagedCompletedOutput[Int],
) -> @execution.ManagedProducerRead[Int] {
  let native = @duckdb.managed_fixed_query_query(query)
  let owner = @duckdb.fixed_query_owner(native)
  let reader = issued_fixture_consumer(
    owner,
    steps="[{\"select\":[\"n\"]}]",
    target=@duckdb.fixed_query_target(native),
  )
  @execution.prepare_managed_producer_read(reader, 0, owner, output, 100, 10000).unwrap()
}

///|
#export_name("ownedFixedRetainedCid")
pub fn owned_fixed_retained_cid(
  value : OwnedFixedFixture,
  output : @execution.CompletedOutput,
) -> String {
  let owner = @duckdb.fixed_query_owner(
    @duckdb.fixed_compute_query(value.compute),
  )
  if @execution.completed_has_cell_access(output) {
    return "null"
  }
  guard @execution.bind_completed_input(
      @execution.generated_sequence_owner(value.consumer),
      0,
      owner,
      output,
    )
    is Ok(_) else {
    return "null"
  }
  match
    @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }) {
    Ok(identity) => @execution.row_wire_cid(identity)
    Err(_) => "null"
  }
}

///|
#export_name("ownedFixedConsumeOutput")
pub fn owned_fixed_consume_output(
  value : OwnedFixedFixture,
  output : @execution.CompletedOutput,
) -> String {
  let owner = @duckdb.fixed_query_owner(
    @duckdb.fixed_compute_query(value.compute),
  )
  guard @execution.bind_completed_input(
      @execution.generated_sequence_owner(value.consumer),
      0,
      owner,
      output,
    )
    is Ok(bound) else {
    return "null"
  }
  guard @execution.execute_generated_sequence(
      value.consumer,
      [],
      issued_execution_limits(100),
      produced=[bound],
    )
    is Ok(completed) else {
    return "null"
  }
  guard @execution.completed_output(completed, @pipeline.Step(0))
    is Some(result) else {
    return "null"
  }
  match
    @execution.identify_completed_rows(result, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }) {
    Ok(identity) => @execution.row_wire_cid(identity)
    Err(_) => "null"
  }
}

///|
#export_name("ownedFixedRowCount")
pub fn owned_fixed_row_count(value : OwnedFixedFixture) -> Int {
  @execution.producer_read_row_count(
    @duckdb.fixed_import_input(
      @duckdb.fixed_compute_import(value.compute, 0).unwrap(),
    ),
  )
}

///|
#export_name("ownedFixedColumnCount")
pub fn owned_fixed_column_count(value : OwnedFixedFixture) -> Int {
  @duckdb.fixed_import_column_count(
    @duckdb.fixed_compute_import(value.compute, 0).unwrap(),
  )
}

///|
#export_name("ownedFixedSql")
pub fn owned_fixed_sql(value : OwnedFixedFixture, kind : Int) -> String {
  let imported = @duckdb.fixed_compute_import(value.compute, 0).unwrap()
  match kind {
    0 => @duckdb.fixed_import_create_sql(imported)
    1 => @duckdb.fixed_import_insert_sql(imported)
    2 => @duckdb.fixed_query_sql(@duckdb.fixed_compute_query(value.compute))
    _ => abort("fixed command selector")
  }
}

///|
#export_name("ownedFixedParameter")
pub fn owned_fixed_parameter(
  value : OwnedFixedFixture,
  row : Int,
  column : Int,
  predicate : Bool,
) -> String {
  let parameter = if predicate {
    @duckdb.fixed_query_parameter(@duckdb.fixed_compute_query(value.compute), 0).unwrap()
  } else {
    match
      @duckdb.fixed_import_parameter(
        @duckdb.fixed_compute_import(value.compute, 0).unwrap(),
        row,
        column,
      ) {
      Ok(value) => value
      Err(_) => return "null"
    }
  }
  try {
    let writer = @encode.writer(10000, 100, 10)
    @duckdb.emit_physical_parameter(parameter, writer)
    @encode.finish(writer)
  } catch {
    _ => "null"
  }
}

///|
#export_name("ownedFixedBegin")
pub fn owned_fixed_begin(
  value : OwnedFixedFixture,
  names : String,
  max_rows : Int,
) -> Bool {
  if value.receiving is Some(_) {
    return false
  }
  match
    @duckdb.prepare_fixed_compute_receiving(
      value.compute,
      fields(names),
      { max_rows, max_cells: 1000, max_nodes: 1000, max_text_bytes: 10000, },
      {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
      10000,
    ) {
    Ok(receiving) => {
      value.receiving = Some(receiving)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("ownedFixedAccept")
pub fn owned_fixed_accept(
  value : OwnedFixedFixture,
  rows : Int,
  data : String,
) -> Bool {
  guard value.receiving is Some(receiving) else { return false }
  @duckdb.receive_fixed_compute_chunk(receiving, rows, columns(data)) is Ok(_)
}

///|
#export_name("ownedFixedFinish")
pub fn owned_fixed_finish(value : OwnedFixedFixture) -> Bool {
  guard value.receiving is Some(receiving) else { return false }
  match @duckdb.finish_fixed_compute_receiving(receiving) {
    Ok(receipt) => {
      match
        @duckdb.measure_fixed_compute_demand(
          value.compute,
          receipt,
          10000,
          issued_native_measure_limits(),
        ) {
        Ok(demand) => value.demand = Some(demand)
        Err(_) => return false
      }
      guard @duckdb.fixed_compute_receipt_rows(receipt) is Some(rows) else {
        return false
      }
      match
        @execution.finish_fixed_producer_measurement(value.measurement, rows) {
        Ok(measured) => value.measured = Some(measured)
        Err(_) => {
          @duckdb.abort_fixed_compute_receiving(receiving)
          return false
        }
      }
      value.receipt = Some(receipt)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("ownedFixedRows")
pub fn owned_fixed_rows(value : OwnedFixedFixture) -> String {
  guard value.receipt is Some(receipt) else { return "null" }
  guard value.demand is Some(demand) &&
    @duckdb.fixed_compute_demand_matches(demand, value.compute, receipt, 10000) else {
    return "null"
  }
  guard @duckdb.fixed_compute_receipt_rows(receipt) is Some(rows) else {
    return "null"
  }
  guard value.measured is Some(measured) &&
    @execution.fixed_producer_measurement_matches(
      measured,
      [
        @duckdb.fixed_import_input(
          @duckdb.fixed_compute_import(value.compute, 0).unwrap(),
        ),
      ],
      rows,
      100,
      10000,
    ) else {
    return "null"
  }
  try {
    let writer = @encode.writer(10000, 1000, 10)
    @encode.begin_array(writer)
    for row in 0..<@execution.admitted_output_row_count(rows) {
      guard @execution.admitted_output_cell(rows, row, 0)
        is Some(@admitted.Number(number)) else {
        return "null"
      }
      @encode.number_value(writer, number)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => "null"
  }
}

///|
#export_name("ownedFixedLocalCid")
pub fn owned_fixed_local_cid(value : OwnedFixedFixture) -> String {
  guard @local_connector.execute_local_fixed_compute(
      value.local_choice,
      value.local_binding,
      issued_execution_limits(100),
      measurement=issued_native_measure_limits(),
    )
    is Ok(completed) else {
    return "null"
  }
  let output = @execution.completed_output(
    completed,
    @duckdb.fixed_query_target(@duckdb.fixed_compute_query(value.compute)),
  ).unwrap()
  guard @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    })
    is Ok(identity) else {
    return "null"
  }
  @execution.row_wire_cid(identity)
}

///|
#export_name("ownedFixedAbort")
pub fn owned_fixed_abort(value : OwnedFixedFixture) -> Unit {
  if value.receiving is Some(receiving) {
    @duckdb.abort_fixed_compute_receiving(receiving)
  }
  value.receipt = None
  value.measured = None
  value.demand = None
}
