///|
test "current paths retain start-major depth order and direction across resume quanta and physical edge permutations" {
  for reverse in [false, true] {
    let nodes = keyed_node_source(
      rows="[{\"id\":1,\"tenant\":\"a\",\"name\":\"one\"},{\"id\":2,\"tenant\":\"a\",\"name\":\"two\"}]",
    )
    let edge_first = "{\"key\":10,\"tenant\":\"a\",\"src\":1,\"dst\":2}"
    let edge_second = "{\"key\":11,\"tenant\":\"a\",\"src\":2,\"dst\":1}"
    let edges = keyed_edge_source(
      rows="[" +
        (if reverse {
          edge_second + "," + edge_first
        } else {
          edge_first + "," + edge_second
        }) +
        "]",
    )
    let graph_owner = keyed_bridge_owner(nodes, edges)
    let construction = @local_bridge.start_rows_to_property_graph(
      @bounded.control(),
      prepared_sequence(graph_owner),
      0,
      keyed_bridge_inputs(graph_owner, nodes, edges),
      { ..carrier_graph_storage_limits(), max_work: 10000, },
      8192L,
      1000,
      () => true,
    ).unwrap()
    let mut retained = None
    for _ in 0..<10000 {
      match @local_bridge.advance_rows_to_graph(construction, 1).unwrap() {
        @local_bridge.Continue(..) => ()
        @local_bridge.Complete(graph, ..) => {
          retained = Some(graph)
          break
        }
        _ => fail("current constructor must complete")
      }
    }
    let graph = retained.unwrap()
    guard @pipeline.carrier_at(
        @lower.pipeline(@lower.bound_preparation(graph_owner)),
        @pipeline.Step(0),
      )
      is Some(@carrier_contract.GraphValue(contract)) else {
      fail("current Graph contract")
    }
    let domain = @carrier_contract.property_graph_domain(
      @carrier_contract.graph_property_definition(contract),
    )
    let node = fn(key : Int) {
      "{\"definition\":\"N\",\"domain\":\"" +
      domain +
      "\",\"key\":[\"a\"," +
      key.to_string() +
      "],\"key_types\":[{\"kind\":\"string\"},{\"kind\":\"number\"}]}"
    }
    let edge = fn(key : Int) {
      "{\"definition\":\"E\",\"domain\":\"" +
      domain +
      "\",\"key\":[" +
      key.to_string() +
      "],\"key_types\":[{\"kind\":\"number\"}]}"
    }
    for mode in ["trail", "walk", "acyclic"] {
      let directions = if mode == "trail" {
        ["out", "in", "both"]
      } else {
        ["out"]
      }
      for direction in directions {
        // Duplicate and reversed starts are an authored selector, not output-derived.
        let body = "[{\"from\":\"g\",\"traverse\":{\"start\":{\"ids\":[" +
          node(2) +
          "," +
          node(1) +
          "," +
          node(2) +
          "]},\"path_mode\":\"" +
          mode +
          "\",\"min_hops\":1,\"max_hops\":" +
          (if mode == "walk" { "3" } else { "2" }) +
          ",\"direction\":\"" +
          direction +
          "\",\"emit\":\"paths\"}}]"
        let owner = keyed_graph_receiver(graph_owner, body~)
        let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
        let preparation = task_test_completion(owner)
        let expected : Array[String] = []
        for start in [1, 2] {
          let next = 3 - start
          let forward = if start == 1 { 10 } else { 11 }
          let backward = 21 - forward
          let first_edges = if direction == "out" {
            [forward]
          } else if direction == "in" {
            [backward]
          } else {
            [10, 11]
          }
          let depths = if mode == "walk" {
            [1, 2, 3]
          } else if mode == "trail" {
            [1, 2]
          } else {
            [1]
          }
          for depth in depths {
            for first in first_edges {
              let edge_ids = if depth == 1 {
                "[" + edge(first) + "]"
              } else if depth == 2 {
                "[" + edge(first) + "," + edge(21 - first) + "]"
              } else {
                "[" +
                edge(first) +
                "," +
                edge(21 - first) +
                "," +
                edge(first) +
                "]"
              }
              let node_ids = if depth == 1 {
                "[" + node(start) + "," + node(next) + "]"
              } else if depth == 2 {
                "[" + node(start) + "," + node(next) + "," + node(start) + "]"
              } else {
                "[" +
                node(start) +
                "," +
                node(next) +
                "," +
                node(start) +
                "," +
                node(next) +
                "]"
              }
              expected.push(
                "{\"edge_ids\":" +
                edge_ids +
                ",\"end_id\":" +
                node(if depth % 2 == 1 { next } else { start }) +
                ",\"hop_count\":" +
                depth.to_string() +
                ",\"node_ids\":" +
                node_ids +
                ",\"start_id\":" +
                node(start) +
                "}",
              )
            }
          }
        }
        for
          (quantum, viewed) in [
            (1, false),
            (7, false),
            (1024, false),
            (1, true),
            (7, true),
          ] {
          let limits : @execution.ValueLimits = {
            max_work: 100000,
            max_nodes: 10000,
            max_text_bytes: 10000,
            max_depth: 50,
          }
          let active = if viewed {
            @local_sga.start_traverse_view(
              @bounded.control(),
              preparation,
              prepared_sequence(owner),
              0,
              @graphs.producer_read_view(input).unwrap(),
              10,
              limits,
              20000,
              10000,
              10000,
              [],
            ).unwrap()
          } else {
            @local_sga.start_traverse(
              @bounded.control(),
              preparation,
              prepared_sequence(owner),
              0,
              input,
              10,
              limits,
              20000,
              10000,
              10000,
              [],
            ).unwrap()
          }
          let output = finish_traverse(active, quantum~).unwrap()
          assert_eq(@execution.completed_row_count(output), expected.length())
          for row, value in expected {
            assert_eq(
              @execution.completed_output_row_wire(
                output, row, 10000, 10000, 50,
              ).unwrap(),
              value,
            )
          }
          assert_true(@local_sga.cleanup_traverse(active).unwrap())
          assert_false(@local_sga.cleanup_traverse(active).unwrap())
          assert_eq(@local_sga.traverse_private_entry_count(active), 0)
          assert_true(@graphs.producer_read_available(input))
        }
      }
    }
    assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
    assert_true(@graphs.discard_completed(graph))
  }
}
