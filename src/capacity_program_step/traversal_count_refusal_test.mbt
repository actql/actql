///|
test "checked traversal execution and registered laws do not establish count applications" {
  let steps = keyed_repeated_measure_steps()
  let producer = graph_measure_pipeline(steps)
  guard @pipeline.output_carrier(producer) is Some(@carrier.GraphValue(graph)) else {
    fail("current keyed Graph constructor")
  }
  let identity = "{\"definition\":\"N\",\"domain\":\"" +
    @carrier.graph_domain(@carrier.graph_definition(graph)) +
    "\",\"key\":[0],\"key_types\":[{\"kind\":\"number\"}]}"
  for
    (body, law) in [
      (
        "{\"traverse\":{\"start\":{\"ids\":[" +
        identity +
        "]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":3,\"path_mode\":\"trail\",\"emit\":\"paths\"}}",
        "actql.bound.traverse-nodes",
      ),
      (
        "{\"shortest_path\":{\"source\":" +
        identity +
        ",\"target\":" +
        identity +
        ",\"direction\":\"out\",\"max_hops\":3}}",
        "actql.bound.shortest-path",
      ),
    ] {
    let checked = graph_measure_pipeline(
      steps.strip_suffix("]").unwrap().to_owned() + "," + body + "]",
    )
    for count in [0L, 1L, 9007199254740991L] {
      let claim = proof(
        law,
        count,
        "{\"op\":\"source\"}",
        reference="checked-step:2",
      )
      assert_true(
        @capacity_program_step.check(checked, 2, claim)
        is Err(UnsupportedOperation),
      )
    }
  }
}
