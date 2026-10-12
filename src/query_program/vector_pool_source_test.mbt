///|
fn vector_pool_control(reduction : String, relation : Bool) -> @program.Program {
  // Authored independently of source compilation. A dynamic assertion supplies
  // Relation member-key evidence; Vectors retains its intrinsic identity role.
  let prefix = if relation {
    "{\"from\":\"candidates\",\"assert_rows\":{\"unique_by\":[\"item_id\"]},\"as\":\"members\"}"
  } else {
    "{\"from\":\"candidates\",\"to_vectors\":{\"id\":\"item_id\",\"vector\":\"embedding\"},\"as\":\"members\"}"
  }
  let body = "{\"by\":[\"label\"],\"method\":\"" +
    reduction +
    "\",\"output_id\":\"pooled_id\"" +
    (if relation { ",\"vector\":\"embedding\"" } else { "" }) +
    "}"
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.vector_pool\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    "{\"values\":{\"schema\":{\"item_id\":{\"type\":\"string\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"item_id\":\"b\",\"embedding\":[0,1],\"label\":\"second\"},{\"item_id\":\"a\",\"embedding\":[1,0],\"label\":\"first\"}]},\"as\":\"candidates\"}," +
    prefix +
    ",{\"from\":\"members\",\"pool_vectors\":" +
    body +
    ",\"as\":\"pooled\"},{\"from\":\"pooled\",\"vectors\":true},{\"sort\":[{\"field\":\"label\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"label\",\"pooled_id\",\"embedding\",\"member_count\"],\"as\":\"answer\"}],\"results\":{\"rows\":{\"from\":\"answer\",\"fields\":[\"label\",\"pooled_id\",\"embedding\",\"member_count\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn vector_pool_checked(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed vector control")
  }
}

///|
test "P2 independent pooling Programs use existing Relation and Vectors common owners" {
  for relation in [false, true] {
    for reduction in ["sum", "mean", "max"] {
      vector_pool_checked(vector_pool_control(reduction, relation))
    }
  }
}

///|
test "P2 pooling source retains argument roles and output columns across both Carriers" {
  for relation in [false, true] {
    for reduction in ["sum", "mean", "max"] {
      let prefix = if relation {
        "FROM candidates |> ASSERT UNIQUE BY (item_id)"
      } else {
        "FROM candidates |> to_vectors(id: item_id, vector: embedding)"
      }
      let text = "WITH members AS (" +
        prefix +
        "), pooled AS (FROM members |> pool_vectors(by: [LABEL], method: '" +
        reduction +
        "', output_id: pooled_id" +
        (if relation { ", vector: EMBEDDING" } else { "" }) +
        ")), rows AS (FROM pooled |> vectors()) SELECT label, pooled_id, embedding, member_count FROM rows ORDER BY label"
      let actual = with_carrier_program(text, nearest_context()).unwrap()
      let expected = vector_pool_control(reduction, relation)
      assert_eq(
        with_carrier_argument(actual, "pool_vectors"),
        with_carrier_argument(expected, "pool_vectors"),
      )
      assert_eq(with_carrier_argument(actual, "vectors"), "true")
      vector_pool_checked(actual)
    }
  }
}
