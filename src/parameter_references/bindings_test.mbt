///|
fn ready(
  declarations : @parameter.Declarations,
  supplied : String,
) -> @parameter.BoundValues {
  match
    @parameter.bind(declarations, Some(cursor(supplied)), {
      max_nodes: 100000,
      max_depth: 20000,
      max_text_bytes: 1000000,
    }).unwrap() {
    @parameter.Ready(v) => v
    _ => abort("test requires complete bindings")
  }
}

///|
fn selected_text(v : BoundIndex, bytes? : Int = 10000) -> String raise {
  let out = @encode.writer(bytes, 1000, 100)
  emit_used_values(v, out)
  @encode.finish(out)
}

///|
test "used values bind exact declarations and preserve typed identity projection" {
  let root = cursor(
    (
      #|{"params":{"p":{"type":"string","format":"duration"},"d":{"type":"decimal","precision":4,"scale":2},"unused":{"type":"string"}},"body":{"p":"$p","p2":"$p","d":"$d","opaque":{"literal":{"$param":"unused"}}}}
    ),
  )
  let declarations = declarations_for(root)
  let body = field(root, "body")
  let index = build(
    body,
    declarations,
    [
      occurrences(field(body, "p")),
      occurrences(field(body, "p2")),
      occurrences(field(body, "d")),
      occurrences(field(body, "opaque")),
    ],
    limits(),
  ).unwrap()
  let values = ready(
    declarations,
    (
      #|{"p":"01S","d":"19.90","unused":"first"}
    ),
  )
  let bound = bind_values(index, values, max_work=5).unwrap()
  let prepared = prepare_values(values, max_work=3).unwrap()
  assert_eq(prepared_work(prepared), 3)
  assert_true(prepare_values(values, max_work=2) is Err(WorkLimit))
  assert_true(prepare_values(values, max_work=-1) is Err(InvalidLimits))
  let reused = bind_prepared(index, prepared, max_work=2).unwrap()
  assert_eq(binding_work(reused), 2)
  assert_eq(selected_text(reused), selected_text(bound))
  assert_true(bind_prepared(index, prepared, max_work=1) is Err(WorkLimit))
  assert_true(bind_prepared(index, prepared, max_work=-1) is Err(InvalidLimits))
  let expected =
    #|{"values":{"d":{"$actql_value":["decimal",{"coefficient":"1990","precision":4,"scale":2,"version":"aoa-decimal-value/0.1"}]},"p":{"$actql_value":["duration",1000]}},"version":"actql-parameter-values/0.1"}
  assert_eq(selected_text(bound), expected)
  assert_eq(reference_count(index), 3)
  assert_eq(used_value_count(bound), 2)
  assert_eq(used_value_at(bound, 0).unwrap().name, "d")
  assert_eq(used_value_at(bound, 1).unwrap().name, "p")
  assert_true(used_value_at(bound, -1) is None)
  assert_true(used_value_at(bound, 2) is None)
  assert_eq(binding_work(bound), 5)
  assert_true(physical_equal(bound_index(bound), index))
  assert_true(physical_equal(bound_values(bound), values))
  assert_true(bind_values(index, values, max_work=4) is Err(WorkLimit))
  assert_true(bind_values(index, values, max_work=-1) is Err(InvalidLimits))
  let equivalent = ready(
    declarations,
    (
      #|{"p":"1000ms","d":"19.90","unused":"different"}
    ),
  )
  assert_eq(
    selected_text(bind_values(index, equivalent, max_work=5).unwrap()),
    expected,
  )
  let changed = ready(
    declarations,
    (
      #|{"p":"1001ms","d":"19.90","unused":"first"}
    ),
  )
  assert_true(
    selected_text(bind_values(index, changed, max_work=5).unwrap()) != expected,
  )
  let foreign = ready(
    declarations_for(root),
    (
      #|{"p":"01S","d":"19.90","unused":"first"}
    ),
  )
  assert_true(
    bind_values(index, foreign, max_work=100) is Err(ForeignDeclarations),
  )
  assert_true(
    bind_prepared(
      index,
      prepare_values(foreign, max_work=3).unwrap(),
      max_work=100,
    )
    is Err(ForeignDeclarations),
  )
  let measured = @encode.measuring_writer(10000, 1000, 100)
  emit_used_values(bound, measured)
  let bytes = @encode.finish_measurement(measured)
  assert_eq(selected_text(bound, bytes~), expected)
  try selected_text(bound, bytes=bytes - 1) catch {
    _ => ()
  } noraise {
    _ => assert_true(false)
  }
  let hashed = @encode.hashing_writer(bytes, 1000, 100)
  emit_used_values(bound, hashed)
  // Independent SHA-256 of the fixed ASCII preimage above.
  assert_eq(
    @encode.finish_hash(hashed),
    "416f5b875a881c7b5fa453fc2c3d2d730b3cfe4adc528e88c545b6c4ee72dcf6",
  )
}

///|
test "empty use set retains the source and binding owners but emits no unused values" {
  let root = cursor(
    (
      #|{"params":{"x":{"type":"number"}},"body":{"literal":{"$param":"x"}}}
    ),
  )
  let declarations = declarations_for(root)
  let body = field(root, "body")
  let index = build(body, declarations, [occurrences(body)], limits()).unwrap()
  let values = ready(declarations, "{\"x\":42}")
  let bound = bind_values(index, values, max_work=1).unwrap()
  assert_eq(used_value_count(bound), 0)
  assert_eq(binding_work(bound), 1)
  assert_eq(
    selected_text(bound),
    (
      #|{"values":{},"version":"actql-parameter-values/0.1"}
    ),
  )
  assert_true(bind_values(index, values, max_work=0) is Err(WorkLimit))
  let empty = @parameter.read_declarations(None, {
    max_parameters: 1,
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 1,
  }).unwrap()
  let no_refs = build(body, empty, [occurrences(body)], limits()).unwrap()
  assert_eq(
    binding_work(bind_values(no_refs, ready(empty, "{}"), max_work=0).unwrap()),
    0,
  )
}
