///|
test "capacity plan quote funds metadata and narrows only scalar wire" {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for
    (name, query, format) in [
      (
        "ordered-offset",
        "SELECT x FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) ORDER BY x LIMIT 1 OFFSET 1",
        @frontend.Sql,
      ),
      (
        "having",
        "SELECT x, COUNT(*) AS n FROM (SELECT 1 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) GROUP BY x HAVING COUNT(*) > 1",
        @frontend.Sql,
      ),
      (
        "pipe",
        "FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) AS t |> WHERE x > 1 |> EXTEND x * 2 AS y |> ORDER BY y DESC |> LIMIT 1 |> SELECT y",
        @frontend.Text,
      ),
      (
        "four-term",
        "SELECT x FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x UNION ALL SELECT 3 AS x UNION ALL SELECT 4 AS x) ORDER BY x",
        @frontend.Sql,
      ),
    ] {
    let lowered = @frontend.lower(
      query,
      format,
      Some(
        @frontend.bind_query_context(
          [],
          "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
        ).unwrap(),
      ),
      public_primary=true,
    ).unwrap()
    let prepared = @publication_host.prepare_effect_free_client_program(
      lowered.document,
      lowered.format,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    let sequences = prepare_client_local_sequences_owned(
      Pure(prepared),
      assets.registry,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let max_rows = @publication_host.prepared_client_values_max_rows(prepared)
    let nodes = client_local_scalar_nodes(sequences, max_rows).unwrap()
    let (values, execution, measurement) = client_local_execution_limits(
      max_rows~,
      scalar_sequences=Some(sequences),
    )
    let mut provider = 0L
    for sequence in sequences {
      let current = @execution.execution_capacity_retained_bytes(
        @execution.generated_sequence_capacity(sequence, execution, measurement).unwrap(),
      )
      if current > provider {
        provider = current
      }
    }
    let graph = @publication_host.prepared_client_graph(prepared)
    let plan = client_local_capacity_plan(
      sequences,
      max_rows,
      scalar_values=true,
      graph=Some(graph),
    )
    assert_true(client_local_capacity_plan_matches(plan, sequences, max_rows))
    assert_false(
      client_local_capacity_plan_matches(plan, sequences, max_rows + 1),
    )
    assert_false(client_local_capacity_plan_matches(plan, [], max_rows))
    assert_eq(plan.imports.wire.max_nodes, values.max_nodes + 3)
    assert_eq(plan.exports.wire.max_nodes, values.max_nodes + 3)
    assert_eq(plan.metadata.schema.max_nodes, 100000)
    assert_eq(plan.metadata.schema.max_bytes,1000000)
    assert_eq(plan.metadata.schema.max_fields,100)
    assert_eq(plan.metadata.bridge_entries, 100000)
    assert_eq(plan.metadata.completion_entries, 100000)
    assert_eq(
      plan.values.max_text_bytes,
      client_local_scalar_name_bytes(sequences, max_rows).unwrap(),
    )
    assert_eq(plan.measurement.max_bytes, 500000)
    assert_eq(plan.imports.wire.max_bytes,client_local_scalar_wire_bytes(sequences,max_rows).unwrap())
    assert_eq(plan.metadata.name_bytes,1000000)
    assert_true(plan.metadata_retained_bytes > 0L)
    assert_eq(plan.metadata.retained_bytes, plan.metadata_retained_bytes)
    let mut terms = 0
    for index in 0..<@strategy.graph_result_count(graph) {
      let occurrence = @strategy.graph_result_occurrence(graph, index).unwrap()
      terms += @results.port_order_term_count(
        @execution.managed_result_occurrence_port(occurrence),
      )
    }
    assert_eq(plan.metadata.result_workspace_entries, 2 * max_rows + terms)
    let mut f = 0
    let mut n = 0
    let mut p = 0
    let mut b = 0
    for sequence in sequences {
      let original = @lower.bound_preparation(@execution.generated_sequence_owner(sequence))
      let inputs = @lower.preparation_input_count(original)
      p=Int::max(p,inputs)
      b=Int::max(b,inputs)
      for index in 0..<inputs {
        let schema = @lower.preparation_input_schema(original,index).unwrap()
        f=Int::max(f,@schema.field_count(schema))
        n=Int::max(n,@schema.field_reference_name_bytes(schema))
      }
      for index in 0..<@lower.node_count(original) {
        let node = @lower.node_at(original,index).unwrap()
        let schema = @lower.node_relation_schema(node).unwrap()
        f=Int::max(f,@schema.field_count(schema))
        n=Int::max(n,@schema.field_reference_name_bytes(schema))
        p=Int::max(p,@lower.node_input_count(node))
        b=Int::max(b,@lower.node_input_count(node))
      }
    }
    let i = @strategy.graph_result_count(graph)+1
    let bridge=p*(3*f+2*b+8)
    let completion=4*p+2*b+64*i+16
    let exported=24*f+2*max_rows+terms+64
    let dispatch=8*p+8*i+64
    let schema_bytes=6*n+96*f+2
    let expected_metadata=(bridge+completion+exported+dispatch).to_int64()*256L+schema_bytes.to_int64()*8L
    assert_eq(plan.metadata_retained_bytes,expected_metadata)
    println("METADATA_PROOF name=\{name} F=\{f} N=\{n} P=\{p} B=\{b} I=\{i} R=\{max_rows} O=\{terms} bridge=\{bridge} completion=\{completion} export=\{exported} dispatch=\{dispatch} schema_bytes=\{schema_bytes}")

    let mut provider = 0L
    for sequence in sequences {
      let actual = @execution.generated_sequence_capacity(
        sequence,
        plan.execution,
        plan.measurement,
      ).unwrap()
      provider = Int64::max(
        provider,
        @execution.execution_capacity_retained_bytes(actual),
      )
    }
    let import_bytes = @local.local_import_retention_capacity(plan.imports).unwrap()
    let export_bytes = @local.local_export_retention_capacity(plan.exports).unwrap()
    let tasks = @strategy.graph_task_count(graph)
    let ports = @strategy.graph_data_count(graph)
    let retained = tasks.to_int64() *
      (provider + export_bytes + plan.metadata_retained_bytes) +
      ports.to_int64() * import_bytes
    let accepted = source_free_installed_managed_preparation_owned(
        Pure(prepared),
        assets.registry,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        false,
      )
      is Some(_)
    assert_eq(accepted, retained <= 536870912L)
    println(
      "CAPACITY_PLAN_QUOTE name=\{name} rows=\{max_rows} nodes=\{nodes} tasks=\{tasks} ports=\{ports} provider=\{provider} import=\{import_bytes} export=\{export_bytes} metadata=\{plan.metadata_retained_bytes} retained=\{retained} accepted=\{accepted}",
    )
  }
}

///|
test "scalar wire capacity byte proof bounds empty rows and checked arithmetic" {
  assert_eq(client_local_scalar_wire_byte_bound(1,2,0),Some(30))
  assert_eq(client_local_scalar_wire_byte_bound(1,2,1),Some(74))
  assert_eq(client_local_scalar_wire_byte_bound(100,1000000,20000),None)
  assert_eq(client_local_scalar_wire_byte_bound(-1,0,1),None)
  assert_eq(client_local_scalar_wire_byte_bound(1,-1,1),None)
  assert_eq(client_local_scalar_wire_byte_bound(1,1,-1),None)
  assert_eq(client_local_scalar_wire_byte_bound(101,1,1),None)
  assert_eq(client_local_scalar_wire_bytes([],100),None)
}

///|
test "capacity plan reports the existing task inventory boundary independently of rows" {
  let assets = @publication_host.client_local_product_assets()
  let evidence="sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f"
  let environment=@publication_host.admit_client_check_environment(assets.environment,evidence,{text_time:true,veca:false},{rela:true,sga:false,tea:false,calendar:false,text_rank:false}).unwrap()
  for terms in [6,7,8] {
    let parts=[]
    for index in 1..<(terms+1) { parts.push("SELECT "+index.to_string()+" AS x") }
    let query="SELECT x FROM ("+parts.join(" UNION ALL ")+") ORDER BY x"
    let lowered=@frontend.lower(query,@frontend.Sql,Some(@frontend.bind_query_context([],evidence).unwrap()),public_primary=true).unwrap()
    let limits=@publication_host.client_standard_program_preparation_limits()
    let ordinary=@publication_host.prepare_effect_free_client_program(lowered.document,lowered.format,environment,None,limits)
    assert_eq(ordinary is Ok(_),terms<8)
    // Test-only diagnostic compilation exposes the checked count beyond the
    // unchanged installed task ceiling; it does not change runtime admission.
    let prepared=@publication_host.prepare_effect_free_client_program(lowered.document,lowered.format,environment,None,{..limits,max_tasks:64}).unwrap()
    let tasks=@strategy.graph_task_count(@publication_host.prepared_client_graph(prepared))
    let admitted=source_free_installed_managed_preparation_owned(Pure(prepared),assets.registry,assets.values,Some(assets.fragment),assets.ordered,false) is Some(_)
    assert_eq(tasks,4*terms+1)
    assert_eq(admitted,terms<8)
    println("TASK_BOUNDARY terms=\{terms} tasks=\{tasks} admitted=\{admitted}")
  }
}
