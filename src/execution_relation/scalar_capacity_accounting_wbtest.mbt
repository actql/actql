///|
fn scalar_accounting_reads(
  width : Int,
  count : Int,
) -> Array[ProducerRead] raise {
  let fields = []
  let cells = []
  for i in 0..<width {
    fields.push(
      "\"k" + i.to_string() + "\":{\"type\":\"number\",\"nullable\":true}",
    )
    cells.push(
      "\"k" + i.to_string() + "\":" + (if i % 2 == 0 { "1" } else { "null" }),
    )
  }
  let schema = "{" + fields.join(",") + "}"
  let row = "{" + cells.join(",") + "}"
  let rows = "[" + Array::make(count, row).join(",") + "]"
  let (owner, output) = bounded_cross_source(schema, rows)
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"l\",\"cross_join\":{\"with\":\"r\",\"select\":{\"k\":\"left.k0\"}}}]",
    ),
    [
      ("l", @pipeline.ProducedInput(producer)),
      ("r", @pipeline.ProducedInput(producer)),
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
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  [
    prepare_producer_read(
      receiver,
      bind_completed_input(receiver, 0, owner, output).unwrap(),
      100,
      10000,
    ).unwrap(),
    prepare_producer_read(
      receiver,
      bind_completed_input(receiver, 1, owner, output).unwrap(),
      100,
      10000,
    ).unwrap(),
  ]
}

///|
test "scalar capacity accounting measures actual binary scanner at exact row-node boundaries" {
  for width in [1, 2, 4] {
    for count in [0, 1, 25, 26, 49, 50, 51, 99, 100] {
      let reads = scalar_accounting_reads(width, count)
      let wire_nodes = 1 + count * (width + 1)
      let wire : RowWireLimits = {
        max_columns: 100,
        max_order_work: 100000,
        max_bytes: 100000,
        max_nodes: wire_nodes,
        max_depth: 100,
      }
      let output = reads[0].bound.output
      let identity = identify_completed_rows(output, wire).unwrap()
      assert_eq(row_wire_usage(identity).1, wire_nodes)
      assert_true(
        identify_completed_rows(output, { ..wire, max_nodes: wire_nodes - 1, })
        is Err(_),
      )
      let table = output.table.unwrap()
      let logical = hash_row_wire(
        table,
        RelationRows::field_names(table),
        { ..wire, max_nodes: wire_nodes + 2, },
        logical=true,
      ).unwrap()
      assert_eq(logical.2, wire_nodes + 2)
      assert_true(
        hash_row_wire(
          table,
          RelationRows::field_names(table),
          { ..wire, max_nodes: wire_nodes + 1, },
          logical=true,
        )
        is Err(_),
      )
      let exact = 2 * count * (width + 1)
      for ceiling in [exact, if exact == 0 { 0 } else { exact - 1 }] {
        let workspace = row_workspace(100)
        let scan = binary_input_scan(
          reads[0],
          reads[1],
          {
            max_nodes: ceiling,
            max_text_bytes: 100000,
            max_depth: 100,
            max_work: 100000,
          },
          { remaining: 100000, max_frames: 100, },
          workspace,
        ).unwrap()
        let mut completed = false
        let mut rejected = false
        for _ in 0..<100000 {
          match advance_binary_input_scan(scan) {
            Ok(true) => {
              completed = true
              break
            }
            Ok(false) => ()
            Err(ValueLimit) => {
              rejected = true
              break
            }
            _ => fail("unexpected scanner failure")
          }
        }
        assert_eq(completed, ceiling == exact)
        assert_eq(rejected, ceiling < exact)
        assert_eq(scan.budget.nodes, ceiling)
        if ceiling == exact {
          assert_eq(workspace.peak, if count == 0 { 0 } else { 1 })
          println(
            "SCALAR_MEASURE rows=\{count} width=\{width} ports=2 actual_nodes=\{scan.budget.nodes} workspace_peak=\{workspace.peak} wire_nodes=\{wire_nodes} logical_wire_nodes=\{logical.2}",
          )
        }
        cleanup_binary_input_scan(scan)
        assert_eq(workspace.live, 0)
        assert_true(producer_read_available(reads[0]))
        assert_true(producer_read_available(reads[1]))
      }
    }
  }
}
