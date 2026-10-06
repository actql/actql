///|
priv enum GraphDefinitionValueFrame {
  Value(@decode.Cursor, Int, Bool)
  ArrayRest(@decode.Cursor, Int, Int, Int)
  ObjectRest(@decode.ObjectView, Array[String], Int, Int, Bool)
}

///|
/// The domain is issued from admitted producer definitions, never from Run
/// bindings or materialized bytes. This projection is not execution authority.
fn graph_element_definition_value(
  at : @decode.Cursor,
  out : @encode.Writer,
  b : Budget,
  depth : Int,
  step_root : Bool,
) -> Unit raise {
  let pending = [GraphDefinitionValueFrame::Value(at, depth, step_root)]
  while pending.pop() is Some(frame) {
    match frame {
      Value(at, depth, step_root) => {
        if depth > b.limits.max_depth {
          fail(at, BudgetExceeded)
        }
        spend(b, at, 1)
        match @decode.view(at) {
          NullValue => @encode.null_value(out)
          BoolValue(value) => @encode.bool_value(out, value)
          NumberValue(value) => @encode.number_value(out, value)
          TextValue(value) => @encode.string_value(out, value)
          ArrayValue(items) => {
            @encode.begin_array(out)
            pending.push(ArrayRest(at, 0, items.length(), depth))
          }
          ObjectValue(object) => {
            let keys = @decode.object_field_names(at).unwrap()
            keys.sort_by(@canonical.compare_utf16)
            @encode.begin_object(out)
            pending.push(ObjectRest(object, keys, 0, depth, step_root))
          }
        }
      }
      ArrayRest(at, index, length, depth) =>
        if index == length {
          @encode.end_array(out)
        } else {
          pending.push(ArrayRest(at, index + 1, length, depth))
          pending.push(
            Value(@decode.element_at(at, index).unwrap(), depth + 1, false),
          )
        }
      ObjectRest(object, keys, index, depth, step_root) =>
        if index == keys.length() {
          @encode.end_object(out)
        } else {
          let key = keys[index]
          pending.push(ObjectRest(object, keys, index + 1, depth, step_root))
          // Mapping fields named "as" or "from" below the root remain
          // semantics. Only pipeline-level coordinates are omitted.
          if !(step_root && (key == "as" || key == "meta" || key == "from")) {
            @encode.key(out, key)
            pending.push(
              Value(@decode.lookup(object, key).unwrap(), depth + 1, false),
            )
          }
        }
    }
  }
}

///|
priv enum GraphProducerDefinitionFrame {
  Target(
    Array[(String, @carrier.Carrier)],
    Array[InputContract],
    Array[ProducedInput?],
    Array[CheckedStep],
    Target,
    Int
  )
  Dependencies(
    Array[(String, @carrier.Carrier)],
    Array[InputContract],
    Array[ProducedInput?],
    Array[CheckedStep],
    Array[InputOccurrence],
    Int,
    Int
  )
  Projection(@relation.CheckedOperation?, Int)
  EndObject
}

///|
fn graph_element_definition_target(
  inputs : Array[(String, @carrier.Carrier)],
  contracts : Array[InputContract],
  produced : Array[ProducedInput?],
  steps : Array[CheckedStep],
  target : Target,
  at : @decode.Cursor,
  out : @encode.Writer,
  b : Budget,
  depth : Int,
) -> Unit raise {
  let pending = [
    GraphProducerDefinitionFrame::Target(
      inputs, contracts, produced, steps, target, depth,
    ),
  ]
  while pending.pop() is Some(frame) {
    match frame {
      EndObject => @encode.end_object(out)
      Projection(projection, depth) => {
        @encode.key(out, "projection")
        match projection {
          None => @encode.null_value(out)
          Some(projection) =>
            graph_element_definition_value(
              @relation.source(projection),
              out,
              b,
              depth,
              false,
            )
        }
      }
      Dependencies(inputs, contracts, produced, steps, entries, index, depth) =>
        if index == entries.length() {
          @encode.end_array(out)
        } else {
          pending.push(
            Dependencies(
              inputs,
              contracts,
              produced,
              steps,
              entries,
              index + 1,
              depth,
            ),
          )
          pending.push(
            Target(
              inputs,
              contracts,
              produced,
              steps,
              entries[index].target,
              depth,
            ),
          )
        }
      Target(inputs, contracts, produced, steps, target, depth) => {
        if depth > b.limits.max_depth {
          fail(at, BudgetExceeded)
        }
        spend(b, at, 1)
        @encode.begin_object(out)
        pending.push(EndObject)
        match target {
          Input(index) => {
            guard inputs.get(index) is Some((name, input)) else {
              fail(at, InvalidBody)
            }
            if produced.get(index).bind(v => v) is Some(owner) {
              @encode.key(out, "producer")
              pending.push(Projection(owner.projection, depth + 1))
              pending.push(
                Target(
                  owner.pipeline.inputs,
                  owner.pipeline.input_contracts,
                  owner.pipeline.produced_inputs,
                  owner.pipeline.steps,
                  owner.target,
                  depth + 1,
                ),
              )
            } else if contracts.get(index)
              is Some(SourceViewInput(_, _, declaration, owner)) {
              @encode.key(out, "source_view")
              @encode.begin_object(out)
              @encode.key(out, "carrier_schema")
              @encode.string_value(
                out,
                @model_environment.carrier_schema_body_cid(
                  @model_environment.source_view_carrier_schema(owner),
                ),
              )
              @encode.key(out, "declaration")
              graph_element_definition_value(
                declaration,
                out,
                b,
                depth + 2,
                false,
              )
              @encode.key(out, "selected_view")
              @encode.string_value(
                out,
                @model_environment.member_cid(
                  @model_environment.reference_member(
                    @model_environment.source_view_carrier_reference(owner),
                  ),
                ),
              )
              @encode.end_object(out)
            } else {
              // A name plus a row schema is not the external producer's admitted
              // definition. Do not fabricate provenance or hash the bound Artifact.
              // The initial vertical accepts retained producer definitions only;
              // external declaration admission must supply its existing owner.
              let _ = (name, input)
              fail(at, MissingPropertyProducerDefinition)
            }
          }
          Step(index) => {
            guard steps.get(index) is Some(step) else { fail(at, InvalidBody) }
            @encode.key(out, "body")
            graph_element_definition_value(step.source, out, b, depth + 1, true)
            @encode.key(out, "dependencies")
            @encode.begin_array(out)
            pending.push(
              Dependencies(
                inputs,
                contracts,
                produced,
                steps,
                step.connections.entries,
                0,
                depth + 1,
              ),
            )
          }
        }
      }
    }
  }
}

///|
// Resolve constructor source coordinates before hashing. The ordered producer
// occurrences below carry provenance; a DATA alias is not definition identity.
fn graph_element_definition_constructor(
  source : @decode.Cursor,
  out : @encode.Writer,
  b : Budget,
) -> Unit raise {
  let root = @decode.open_object(source).unwrap()
  let nodes = @decode.elements(@decode.lookup(root, "nodes").unwrap()).unwrap()
  let edges = @decode.elements(@decode.lookup(root, "edges").unwrap()).unwrap()
  @encode.begin_object(out)
  for
    (branch, elements, offset) in [
      ("edges", edges, nodes.length()),
      ("nodes", nodes, 0),
    ] {
    @encode.key(out, branch)
    @encode.begin_array(out)
    spend(b, source, elements.length())
    for index, element in elements {
      let object = @decode.open_object(element).unwrap()
      let keys = @decode.object_field_names(element)
        .unwrap()
        .filter(key => key != "from")
      keys.push("input_occurrence")
      keys.sort_by(@canonical.compare_utf16)
      spend(b, element, keys.length())
      @encode.begin_object(out)
      for key in keys {
        @encode.key(out, key)
        if key == "input_occurrence" {
          @encode.number_value(out, (offset + index).to_double())
        } else {
          // Property-column mappings named "from" remain semantic fields.
          graph_element_definition_value(
            @decode.lookup(object, key).unwrap(),
            out,
            b,
            3,
            false,
          )
        }
      }
      @encode.end_object(out)
    }
    @encode.end_array(out)
  }
  @encode.key(out, "version")
  let version = match @decode.lookup(root, "version") {
    Some(version) => version
    None => fail(source, InvalidBody)
  }
  graph_element_definition_value(version, out, b, 1, false)
  @encode.end_object(out)
}

///|
fn graph_element_definition_domain(
  source : @decode.Cursor,
  inputs : Array[(String, @carrier.Carrier)],
  contracts : Array[InputContract],
  produced : Array[ProducedInput?],
  steps : Array[CheckedStep],
  targets : Array[Target],
  b : Budget,
) -> String raise Stop {
  try {
    let out = @encode.hashing_writer(b.text, b.nodes, b.limits.max_depth)
    @encode.begin_object(out)
    @encode.key(out, "constructor")
    graph_element_definition_constructor(source, out, b)
    @encode.key(out, "producer_definitions")
    @encode.begin_array(out)
    for target in targets {
      graph_element_definition_target(
        inputs, contracts, produced, steps, target, source, out, b, 0,
      )
    }
    @encode.end_array(out)
    @encode.key(out, "version")
    @encode.string_value(out, "actql-graph-definition/0.1")
    @encode.end_object(out)
    let (hash, bytes, nodes, _) = @encode.finish_hash_metrics(out)
    spend(b, source, nodes)
    b.nodes -= nodes
    b.text -= bytes
    "sha256:" + hash
  } catch {
    Stop(issue) => raise Stop(issue)
    _ => fail(source, BudgetExceeded)
  }
}

///|
fn check_graph_step(
  body : @decode.Cursor,
  at : @decode.Cursor,
  object : @decode.ObjectView,
  names : Map[String, Target],
  inputs : Array[(String, @carrier.Carrier)],
  contracts : Array[InputContract],
  produced : Array[ProducedInput?],
  steps : Array[CheckedStep],
  b : Budget,
) -> CheckedStep raise Stop {
  if @decode.lookup(object, "from") is Some(from) {
    fail(from, GeneratorFrom)
  }
  let binding = match @decode.lookup(object, "as") {
    Some(source) => read_name(b, source)
    None => fail(body, GeneratorRequiresAlias)
  }
  if names.contains(binding) {
    fail(body, DuplicateName(binding))
  }
  let config = match @decode.closed_object(at, ["version", "nodes", "edges"]) {
    Ok(value) => value
    Err(_) => fail(at, InvalidBody)
  }
  let targets = []
  let schemas = []
  let seen : Map[String, Bool] = Map([])
  for branch in ["nodes", "edges"] {
    let list = match @decode.required(config, branch) {
      Ok(value) => value
      Err(_) => fail(at, InvalidBody)
    }
    let elements = match @decode.elements(list) {
      Ok(value) => value
      Err(_) => fail(list, InvalidBody)
    }
    spend(b, list, elements.length())
    for element in elements {
      let definition = match @decode.open_object(element) {
        Ok(value) => value
        Err(_) => fail(element, InvalidBody)
      }
      let from = match @decode.required(definition, "from") {
        Ok(value) => value
        Err(_) => fail(element, InvalidBody)
      }
      let name = read_name(b, from)
      let target = resolve_target(b, from, names)
      targets.push(target)
      if !seen.contains(name) {
        schemas.push((name, carrier(target, inputs, steps)))
        seen[name] = true
      }
    }
  }
  let domain = graph_element_definition_domain(
    at, inputs, contracts, produced, steps, targets, b,
  )
  let checked = match
    @graph.check_property_construction(at, schemas, domain, {
      max_work: b.work,
      max_nodes: b.nodes,
      max_depth: b.limits.max_depth,
      max_text_bytes: b.text,
    }) {
    Ok(value) => value
    Err(issue) =>
      raise Stop({
        kind: Graph(issue.kind),
        source: at,
        path: issue.path.copy(),
        span: issue.span,
        range: None,
      })
  }
  let used = @graph.construction_usage(checked)
  b.work -= used.work
  b.nodes -= used.nodes
  b.text -= used.text_bytes
  let meta = @decode.lookup(object, "meta")
  if meta is Some(meta) {
    metadata(b, meta)
  }
  {
    source: body,
    input: None,
    binding_name: Some(binding),
    metadata: meta,
    operation: GraphConstruction(inputs=targets, checked~),
    output: @graph.construction_output(checked),
    connections: {
      entries: targets.mapi((index, target) => { role: Sample(index), target, }),
    },
    window: None,
  }
}
