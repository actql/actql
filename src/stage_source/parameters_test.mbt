///|
fn parameter_caps() -> @collection.Limits {
  {
    max_work: 4000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 100000,
    max_direct_text_bytes: 100000,
  }
}

///|
test "stage operation and Effect holes share one owned reference index" {
  let body = prepare(
    collected(
      (
        #|,"effects":{"u":{"update":{"max_items":{"$param":"n"},"where":["amount > $n"],"set":{"x":{"literal":{"$param":"n"}},"y":{"literal":{"nested":{"$param":"missing"}}}}}},"c":{"command":{"input":{"x":{"literal":{"$param":"n"}},"y":{"field":"n"}}}},"d":{"delete":{"ids":[{"$param":"n"},2,{"$param":"n"}]}},"e":{"delete":{"external_id":{"field":"id","value":{"$param":"n"}}}},"payload":{"create":{"payload":{"literal":{"$param":"missing"},"meta":{"$param":"missing"}}}}}
      ),
      step_text="[{\"take\":{\"$param\":\"n\"}}]",
    ),
    caps(),
  ).unwrap()
  let uses = collect_parameter_uses(body, parameter_caps()).unwrap()
  assert_true(physical_equal(parameter_body(uses), body))
  let index = parameter_index(uses)
  assert_true(
    physical_equal(
      @references.declarations(index),
      @stages.declarations(@stages.source(stage(body))),
    ),
  )
  let paths = []
  for i in 0..<@references.reference_count(index) {
    let reference = @references.reference_at(index, i).unwrap()
    assert_eq(reference.name, "n")
    paths.push(reference.path)
  }
  assert_eq(paths, [
    "/effects/c/command/input/x/literal", "/effects/d/delete/ids/0", "/effects/d/delete/ids/2",
    "/effects/e/delete/external_id/value", "/effects/u/update/max_items", "/effects/u/update/set/x/literal",
    "/effects/u/update/where/0/gt/1", "/steps/0/take",
  ])
  let declarations = @encode.writer(10000, 1000, 100)
  @references.emit_used_declarations(index, declarations)
  assert_eq(@encode.finish(declarations), "{\"n\":{\"type\":\"number\"}}")
  let exact = parameter_work(uses)
  assert_true(
    collect_parameter_uses(body, { ..parameter_caps(), max_work: exact, })
    is Ok(_),
  )
  assert_true(
    collect_parameter_uses(body, { ..parameter_caps(), max_work: exact - 1, })
    is Err(_),
  )
  assert_true(
    collect_parameter_uses(body, { ..parameter_caps(), max_references: 7, })
    is Err(References(ReferenceLimit)),
  )
  assert_true(
    collect_parameter_uses(body, { ..parameter_caps(), max_slots: 7, })
    is Err(References(SlotLimit)),
  )
  assert_true(
    collect_parameter_uses(body, { ..parameter_caps(), max_pointer_units: 0, })
    is Err(References(PointerLimit)),
  )
  assert_true(
    collect_parameter_uses(body, {
      ..parameter_caps(),
      max_direct_text_bytes: 0,
    })
    is Err(_),
  )
}

///|
test "whole ID array holes and immediate Effect literals are not recursive templates" {
  let body = prepare(
    collected(
      (
        #|,"effects":{"d":{"delete":{"ids":{"$param":"n"}}},"u":{"upsert":{"set":{"direct":{"literal":{"$param":"n"}},"quoted":{"literal":{"literal":{"$param":"missing"}}},"array":{"literal":[{"$param":"missing"}]},"two":{"literal":{"$param":"missing","other":0}}}}}}
      ),
    ),
    caps(),
  ).unwrap()
  let index = parameter_index(
    collect_parameter_uses(body, parameter_caps()).unwrap(),
  )
  assert_eq(@references.reference_count(index), 2)
  assert_eq(
    @references.reference_at(index, 0).unwrap().path,
    "/effects/d/delete/ids",
  )
  assert_eq(
    @references.reference_at(index, 1).unwrap().path,
    "/effects/u/upsert/set/direct/literal",
  )
  // Reference discovery does not validate n as an ID array or mapped value;
  // it retains the declared number type for later consumer admission.
  assert_eq(@references.reference_at(index, 0).unwrap().name, "n")
  let missing = prepare(
    collected(
      ",\"effects\":{\"u\":{\"update\":{\"set\":{\"x\":{\"literal\":{\"$param\":\"missing\"}}}}}}",
    ),
    caps(),
  ).unwrap()
  assert_true(
    collect_parameter_uses(missing, parameter_caps())
    is Err(
      References(UnknownParameter("missing", "/effects/u/update/set/x/literal"))
    ),
  )
  let malformed = prepare(
    collected(
      ",\"effects\":{\"u\":{\"update\":{\"max_items\":{\"$param\":42}}}}",
    ),
    caps(),
  ).unwrap()
  assert_true(
    collect_parameter_uses(malformed, parameter_caps()) is Err(Syntax(_)),
  )
}

///|
test "normalized selector Parameter paths agree across text and structured notation" {
  let textual = prepare(
    collected(
      (
        #|,"effects":{"u":{"delete":{"where":["amount > $n"]}}}
      ),
    ),
    caps(),
  ).unwrap()
  let structured = prepare(
    collected(
      (
        #|,"effects":{"u":{"delete":{"where":[{"gt":[{"field":"amount"},{"$param":"n"}]}]}}}
      ),
    ),
    caps(),
  ).unwrap()
  assert_eq(rendered(textual), rendered(structured))
  let outputs = []
  for body in [textual, structured] {
    let uses = collect_parameter_uses(body, parameter_caps()).unwrap()
    let writer = @encode.writer(10000, 1000, 100)
    @references.emit_references(parameter_index(uses), writer)
    outputs.push(@encode.finish(writer))
  }
  assert_eq(outputs[0], outputs[1])
  assert_eq(
    outputs[0],
    "[{\"name\":\"n\",\"path\":\"/effects/u/delete/where/0/gt/1\",\"type\":{\"type\":\"number\"}}]",
  )
  assert_true(
    collect_parameter_uses(textual, { ..parameter_caps(), max_slots: -1, })
    is Err(InvalidLimits),
  )
}
