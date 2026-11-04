///|
test "restored Content reserves overlapping admissions and authenticated metadata" {
  // Row slots; value, wire and two decoded representations; five byte
  // envelopes. Both admissions may overlap while the original remains held.
  let importing = 64L * (100L + 20000L + 100000L + 100L + 100000L + 100000L) +
    8L * (1000000L + 1000000L + 1000000L + 1000000L + 1000000L)
  assert_eq(importing, 60492800L)
  let capacity = client_retained_content_capacity().unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 68638464L)
  // The receiving accounting frame adds eight fixed 64-byte control slots,
  // only during execution, not to durable value retention.
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity),
    140711488L + 8L * 64L,
  )
}

///|
test "Content completion transport reserves export and retained record overlap" {
  // Fixed row wire, reference roots, batch and column/depth cursors. Saved
  // row text, two 8192-byte metadata bodies and 228 roots remain afterwards.
  let exporting = 1024L +
    1000000L +
    128L * 20000L +
    8L * 1000000L +
    64L * (100L + 100L + 100L)
  let retained = 8L * (1000000L + 2L * 8192L) + 64L * (100L + 128L)
  assert_eq(exporting, 11580224L)
  assert_eq(retained, 8145664L)
  let capacity = client_content_completion_export_capacity().unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), retained)
  assert_eq(@execution.execution_capacity_execution_bytes(capacity), 19725888L)
}

///|
test "retained inventory admits exact capacity and rejects one short" {
  // Three outputs: 3 * (10 provider + 7 export), three input ports: 3 * 5.
  assert_eq(
    client_local_store_inventory([0, 1, 2], 10L, 5L, 7L, 66L),
    Some((66L, 3L)),
  )
  assert_true(client_local_store_inventory([0, 1, 2], 10L, 5L, 7L, 65L) is None)
  assert_eq(
    client_local_store_inventory([0], 10L, 5L, 7L, 17L),
    Some((17L, 0L)),
  )
  assert_true(client_local_store_inventory([0], 10L, 5L, 7L, 16L) is None)
}

///|
test "retained inventory counts repeated producer ports without sharing" {
  assert_eq(
    client_local_store_inventory([0, 2, 1, 1], 10L, 5L, 7L, 88L),
    Some((88L, 4L)),
  )
  assert_true(
    client_local_store_inventory([0, 2, 1, 1], 10L, 5L, 7L, 87L) is None,
  )
}

///|
test "installed Store limits cover the eight task Set publication inventory" {
  let (values, _, _) = client_local_execution_limits()
  let imports = client_local_import_limits(
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    values,
  )
  // Independent fixture inventory: row slots; admitted, wire and decoded
  // nodes; columns; one extra per-row reference view; five byte envelopes.
  let import_bytes = 64L * (100L + 20000L + 100000L + 100L + 10000L + 10000L) +
    8L * (500000L + 1000000L + 65536L + 65536L + 65536L)
  assert_eq(import_bytes, 22545664L)
  assert_eq(@local.local_import_retention_capacity(imports), Some(import_bytes))
  // Preparation roots, canonical bytes, exact authority/reference roots,
  // one batch and bounded column/depth continuation metadata.
  let export_bytes = 1024L +
    1000000L +
    128L * 20000L +
    8L * 65536L +
    64L * (100L + 64L + 100L)
  assert_eq(export_bytes, 4102208L)
  assert_eq(
    @local.local_export_retention_capacity(
      client_local_export_limits(100, values),
    ),
    Some(export_bytes),
  )
  // Eight outputs and eight ports (including both Set inputs), not six
  // authored producer operations alone. The 512 MiB ceiling is unchanged.
  assert_eq(
    client_local_store_inventory(
      [0, 1, 2, 1, 1, 1, 1, 1],
      14240000L,
      import_bytes,
      export_bytes,
      536870912L,
    ),
    Some((327102976L, 8L)),
  )
  // Eight producer+export allocations and eight receiving copies. This is
  // independent of the implementation's measured/returned capacity value.
  assert_eq(8L * (14240000L + export_bytes) + 8L * import_bytes, 327102976L)
  assert_true(
    client_local_store_inventory(
      [0, 1, 2, 1, 1, 1, 1, 1],
      14240000L,
      import_bytes,
      export_bytes,
      327102975L,
    )
    is None,
  )
  // A larger inventory still fails before opening a Run; no limit increase.
  assert_true(
    client_local_store_inventory(
      Array::make(32, 1),
      14240000L,
      import_bytes,
      export_bytes,
      536870912L,
    )
    is None,
  )
}

///|
test "retained inventory rejects invalid and overflowing capacities" {
  for inputs in [[-1], [1, -1]] {
    assert_true(client_local_store_inventory(inputs, 0L, 0L, 0L, 10L) is None)
  }
  assert_true(client_local_store_inventory([1], -1L, 0L, 0L, 10L) is None)
  assert_true(client_local_store_inventory([1], 0L, -1L, 0L, 10L) is None)
  assert_true(client_local_store_inventory([1], 0L, 0L, -1L, 10L) is None)
  assert_true(client_local_store_inventory([1], 0L, 0L, 0L, -1L) is None)
  assert_true(
    client_local_store_inventory(
      [1],
      9223372036854775807L,
      0L,
      1L,
      9223372036854775807L,
    )
    is None,
  )
  assert_true(
    client_local_store_inventory(
      [2147483647],
      0L,
      9223372036854775807L,
      0L,
      9223372036854775807L,
    )
    is None,
  )
}

///|
test "family reservations include predecessor overlap and every retained envelope" {
  // Three fixed task reservations: provider output 10, export 7, one import
  // of 5 per port, scratch 2/3/4. The reservations are 19, 25 and 31, not
  // max(19, 25, 31). Retention is 17 + 22 + 27 = 66; execution is 75.
  let mut inventory = (0L, 0L)
  for (ports, scratch) in [(0, 2L), (1, 3L), (2, 4L)] {
    inventory = client_local_family_task_inventory(
      inventory, 10L, scratch, ports, 5L, 7L, 75L,
    ).unwrap()
  }
  assert_eq(inventory, (66L, 75L))
  let first = client_local_family_task_inventory(
    (0L, 0L),
    10L,
    2L,
    0,
    5L,
    7L,
    74L,
  ).unwrap()
  assert_eq(first, (17L, 19L))
  let second = client_local_family_task_inventory(
    first, 10L, 3L, 1, 5L, 7L, 74L,
  ).unwrap()
  assert_eq(second, (39L, 44L))
  assert_true(
    client_local_family_task_inventory(second, 10L, 4L, 2, 5L, 7L, 74L) is None,
    msg="one-short whole-Run budget cannot release or forget a predecessor",
  )
  // Repeated producer occurrences are separate ports, even when the provider
  // output is shared logically. Four tasks retain 88; scratch adds 14.
  let mut repeated = (0L, 0L)
  for (ports, scratch) in [(0, 2L), (2, 3L), (1, 4L), (1, 5L)] {
    repeated = client_local_family_task_inventory(
      repeated, 10L, scratch, ports, 5L, 7L, 102L,
    ).unwrap()
  }
  assert_eq(repeated, (88L, 102L))
}

///|
test "family reservation inventory rejects invalid quantities and overflow" {
  for (retained, executing) in [(-1L, 0L), (0L, -1L), (11L, 0L), (0L, 11L)] {
    assert_true(
      client_local_family_task_inventory(
        (retained, executing),
        0L,
        0L,
        0,
        0L,
        0L,
        10L,
      )
      is None,
    )
  }
  for
    (bytes, scratch, imports, exports, ports, ceiling) in [
      (-1L, 0L, 0L, 0L, 0, 10L),
      (0L, -1L, 0L, 0L, 0, 10L),
      (0L, 0L, -1L, 0L, 0, 10L),
      (0L, 0L, 0L, -1L, 0, 10L),
      (0L, 0L, 0L, 0L, -1, 10L),
      (0L, 0L, 0L, 0L, 0, -1L),
    ] {
    assert_true(
      client_local_family_task_inventory(
        (0L, 0L),
        bytes,
        scratch,
        ports,
        imports,
        exports,
        ceiling,
      )
      is None,
    )
  }
  let maximum = 9223372036854775807L
  assert_true(
    client_local_family_task_inventory(
      (0L, 0L),
      maximum,
      1L,
      0,
      0L,
      0L,
      maximum,
    )
    is None,
  )
  assert_true(
    client_local_family_task_inventory(
      (0L, 0L),
      0L,
      0L,
      2147483647,
      maximum,
      0L,
      maximum,
    )
    is None,
  )
  assert_true(
    client_local_family_task_inventory(
      (0L, maximum),
      1L,
      0L,
      0,
      0L,
      0L,
      maximum,
    )
    is None,
  )
  assert_eq(
    client_local_family_task_inventory(
      (0L, 0L),
      maximum - 1L,
      1L,
      0,
      0L,
      0L,
      maximum,
    ),
    Some((maximum - 1L, maximum)),
  )
}

///|
test "single capture inventory retains Native beside the Compute allowance" {
  let compute : @resources.LedgerLimits = {
    planning_work: 100,
    attempts: 3,
    holdings: 3,
    transfer_bytes: 3000L,
    retained_bytes: 200000000L,
    execution_bytes: 536870912L,
  }
  let planned = single_captured_capacity_limits(
    compute,
    (139000000L, 100000000L),
  ).unwrap()
  assert_eq(planned.retained_bytes, 339000000L)
  assert_eq(planned.execution_bytes, 536870912L)
  assert_eq(planned.transfer_bytes, 3000L)
  assert_eq(planned.attempts, 3)
  // An exactly full inventory is allowed; one byte over is not.
  assert_eq(
    single_captured_capacity_limits(compute, (336870912L, 0L)).unwrap().retained_bytes,
    536870912L,
  )
  for native in [(336870913L, 0L), (-1L, 0L), (0L, -1L), (0L, 536870913L)] {
    assert_true(single_captured_capacity_limits(compute, native) is None)
  }
}

///|
test "Source-free whole-run maximum does not veto finite runtime admission" {
  let assets = @publication_host.client_local_product_assets()
  let evidence = "sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261"
  let environment = @publication_host.admit_client_check_environment(
    closed_carrier_demand_environment,
    evidence,
    { text_time: true, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    graph=true,
  ).unwrap()
  let catalog = @checked.prepare_source_catalog(environment, {
    max_work: 1000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }).unwrap()
  let query = "WITH n AS (SELECT node_key, node_key AS seed FROM UNNEST([3, 2, 1]) node_key) , e AS (SELECT 13 AS edge_key, 2 AS src, 3 AS dst UNION ALL SELECT 12 AS edge_key, 1 AS src, 1 AS dst UNION ALL SELECT 11 AS edge_key, 1 AS src, 2 AS dst UNION ALL SELECT 10 AS edge_key, 1 AS src, 2 AS dst) , g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (seed)) EDGE TABLES (e AS E KEY (edge_key) SOURCE KEY (src) REFERENCES N DESTINATION KEY (dst) REFERENCES N LABEL R NO PROPERTIES))) , reached AS (FROM g |> reach(start: {where: 'seed = 1'}, direction: 'out', max_depth: 2)) FROM reached |> SELECT depth |> ORDER BY depth |> RESULT reached"
  let lowered = match
    @frontend.lower(
      query,
      @frontend.Text,
      Some(
        @frontend.bind_query_context(
          [],
          evidence,
          source_catalog=Some(@checked.source_catalog_contracts(catalog)),
        ).unwrap(),
      ),
      public_primary=true,
    ) {
    Ok(value) => value
    Err(@frontend.QuerySyntax(issue)) =>
      fail("original Graph syntax: " + @debug.to_string(issue))
    Err(@frontend.QueryLowering(_)) => fail("original Graph lowering")
    Err(_) => fail("original Graph frontend")
  }
  let prepared = match
    @publication_host.prepare_effect_free_client_program(
      lowered.document,
      lowered.format,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
      source_catalog=Some(catalog),
    ) {
    Ok(value) => value
    Err(@publication_host.Check(issue)) =>
      fail(
        "original Graph check: " +
        @debug.to_string(@checked.diagnostic_category(issue)) +
        ": " +
        (match @checked.diagnostic_cause(issue) {
          @checked.Units(_) => "Units"
          @checked.Closure(_) => "Closure"
          @checked.Source(_) => "Source"
          @checked.Program(_) => "Program"
          @checked.CapacityInputs(_) => "CapacityInputs"
          @checked.Environment(_) => "Environment"
          @checked.Template(_, _) => "Template"
          @checked.InvalidLimits => "InvalidLimits"
        }),
      )
    Err(@publication_host.Syntax(_)) => fail("original Graph Program syntax")
    Err(@publication_host.NeedsInputs(_)) => fail("original Graph NeedsInputs")
    Err(@publication_host.Graph(_)) => fail("original Graph task construction")
    Err(_) => fail("original Graph preparation")
  }
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = source_free_installed_managed_preparation_owned(
    Pure(prepared),
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    false,
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  let inputs = Array::make(count, 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    inputs[@strategy.data_edge_consumer(edge)] += 1
  }
  // The old whole-future envelope cannot fit. It is still required by callers
  // selecting that envelope, rather than silently converted to a small quote.
  assert_true(
    client_local_sequence_capacity_original(
      original.sequences,
      count,
      capacity_plan=Some(original.capacity_plan),
      retained_inputs=Some(inputs),
      max_rows=@publication_host.prepared_client_values_max_rows(prepared),
    )
    is None,
  )
  assert_eq(original.limits.retained_bytes, 536870912L)
  assert_true(
    client_local_sequence_capacity_original(
      original.sequences,
      count,
      capacity_plan=Some(original.capacity_plan),
      retained_inputs=Some([]),
      max_rows=@publication_host.prepared_client_values_max_rows(prepared),
      runtime_admission=true,
    )
    is None,
  )
}
