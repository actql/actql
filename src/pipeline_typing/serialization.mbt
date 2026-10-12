///|
/// Common byte semantics plus the existing checked sort; not completed input,
/// byte custody, a Ref issuer or permission to publish.
struct CheckedSerialization {
  source : @decode.Cursor
  input : @schema.Schema
  output : @schema.Schema
  profile : @content.ContentSerializationProfile
  sort : @relation.CheckedOperation?
  max_rows : @relation.CheckedCountValue?
  max_bytes : @relation.CheckedCountValue?
}

///|
pub fn serialization_source(value : CheckedSerialization) -> @decode.Cursor {
  value.source
}

///|
pub fn serialization_profile(
  value : CheckedSerialization,
) -> @content.ContentSerializationProfile {
  value.profile
}

///|
pub fn serialization_input_schema(
  value : CheckedSerialization,
) -> @schema.Schema {
  value.input
}

///|
pub fn serialization_sort(
  value : CheckedSerialization,
) -> @relation.CheckedOperation? {
  value.sort
}

///|
pub fn serialization_max_rows(
  value : CheckedSerialization,
) -> @relation.CheckedCountValue? {
  value.max_rows
}

///|
pub fn serialization_max_bytes(
  value : CheckedSerialization,
) -> @relation.CheckedCountValue? {
  value.max_bytes
}

///|
fn serialization_guard(
  b : Budget,
  object : @decode.ObjectView,
  key : String,
  parameters : @parameter.Declarations?,
) -> @relation.CheckedCountValue? raise Stop {
  guard @decode.lookup(object, key) is Some(at) else { return None }
  let checked = match
    @relation.check_count_value(at, 1L, parameters, {
      max_work: b.work,
      max_nodes: b.nodes,
      max_text_bytes: b.text,
      max_depth: b.limits.max_depth,
      max_tokens: b.tokens,
    }) {
    Ok(value) => value
    Err(e) => fail(e.source, Operation(e.kind))
  }
  let (work, text) = @relation.count_value_usage(checked)
  spend(b, at, work)
  b.text -= text
  Some(checked)
}

///|
fn check_serialization(
  b : Budget,
  at : @decode.Cursor,
  input : @schema.Schema,
  parameters : @parameter.Declarations?,
) -> CheckedSerialization raise Stop {
  let object = match
    @decode.closed_object(at, [
      "format", "fields", "order_by", "preserve_order", "name", "header", "null_marker",
      "field_delimiter", "encoding", "line_ending", "bounds",
    ]) {
    Ok(object) => object
    Err(_) => fail(at, InvalidBody)
  }
  spend(b, at, @decode.object_field_names(at).unwrap().length())
  let format = match
    @decode.lookup(object, "format").bind(value => {
      @decode.text(value).to_option()
    }) {
    Some("csv") => @content.ContentCsv
    Some("jsonl") => @content.ContentJsonl
    _ => fail(at, Serialize(@content.ContentInvalidOption("format")))
  }
  guard @decode.lookup(object, "fields") is Some(fields_at) else {
    fail(at, Serialize(@content.ContentInvalidFields))
  }
  let fields = match @decode.elements(fields_at) {
    Ok(values) => values
    Err(_) => fail(fields_at, Serialize(@content.ContentInvalidFields))
  }
  spend(b, fields_at, fields.length())
  let names = fields.map(value => {
    let name = match @decode.text(value) {
      Ok(name) => name
      Err(_) => fail(value, Serialize(@content.ContentInvalidFields))
    }
    charge(b, value, name)
    name
  })
  let sort = match
    (
      @decode.lookup(object, "order_by"),
      @decode.lookup(object, "preserve_order"),
    ) {
    (Some(order), None) => {
      guard @decode.elements(order) is Ok(terms) && !terms.is_empty() else {
        fail(order, SerializeOrderUnproven)
      }
      let checked = match
        @relation.check(Sort, order, input, parameters, {
          max_work: b.work,
          max_nodes: b.nodes,
          max_text_bytes: b.text,
          max_tokens: b.tokens,
          max_depth: b.limits.max_depth,
        }) {
        Ok(value) => value
        Err(e) =>
          raise Stop({
            kind: Operation(e.kind),
            source: e.source,
            path: e.path.copy(),
            span: e.span,
            range: e.range,
          })
      }
      b.work -= @relation.work_used(checked)
      b.nodes -= @relation.nodes_used(checked)
      b.text -= @relation.text_bytes_used(checked)
      b.tokens -= @relation.tokens_used(checked)
      Some(checked)
    }
    (None, Some(value)) if @decode.view(value) is @decode.BoolValue(true) =>
      None
    _ => fail(at, SerializeOrderUnproven)
  }
  let profile = try {
    let out = @encode.writer(b.text, b.nodes, b.limits.max_depth)
    @encode.begin_object(out)
    for
      key in [
        "name", "header", "null_marker", "field_delimiter", "encoding", "line_ending",
      ] {
      if @decode.lookup(object, key) is Some(value) {
        spend(b, value, 1)
        @encode.key(out, key)
        match @decode.view(value) {
          TextValue(text) => {
            charge(b, value, text)
            @encode.string_value(out, text)
          }
          BoolValue(v) => @encode.bool_value(out, v)
          _ => fail(value, Serialize(@content.ContentInvalidOption(key)))
        }
      }
    }
    @encode.end_object(out)
    let wire = @encode.finish(out)
    match
      @content.prepare_content_serialization_profile(
        format,
        input,
        names,
        wire,
        {
          max_fields: b.nodes,
          max_name_bytes: b.text,
          max_work: b.work,
          max_options_bytes: b.text,
          max_options_nodes: b.nodes,
          max_options_depth: b.limits.max_depth,
        },
      ) {
      Ok(profile) => profile
      Err(issue) => fail(at, Serialize(issue))
    }
  } catch {
    Stop(issue) => raise Stop(issue)
    _ => fail(at, BudgetExceeded)
  }
  spend(b, at, @content.content_serialization_profile_work(profile))
  if names.length() > b.nodes {
    fail(at, BudgetExceeded)
  }
  b.nodes -= names.length()
  let text = @contract.primitive(StringType, nullable=false)
  let number = @contract.primitive(NumberType, nullable=false)
  let reference = @contract.content_reference_contract(
    Some(@content.content_serialization_media_type(profile)),
    nullable=false,
    max_name_bytes=100,
  ).unwrap()
  let output = match
    @schema.from_fields(
      [
        (Unqualified("name"), text),
        (Unqualified("content"), reference),
        (Unqualified("media_type"), text),
        (Unqualified("size_bytes"), number),
        (Unqualified("row_count"), number),
      ],
      max_fields=5,
      max_name_bytes=100,
    ) {
    Ok(value) => value
    Err(_) => fail(at, InvalidBody)
  }
  let (max_rows, max_bytes) = match @decode.lookup(object, "bounds") {
    None => (None, None)
    Some(bounds_at) => {
      let bounds = match
        @decode.closed_object(bounds_at, ["max_rows", "max_bytes"]) {
        Ok(value) => value
        Err(_) => fail(bounds_at, InvalidBody)
      }
      let count = @decode.object_field_names(bounds_at).unwrap().length()
      if count == 0 {
        fail(bounds_at, InvalidBody)
      }
      spend(b, bounds_at, count)
      (
        serialization_guard(b, bounds, "max_rows", parameters),
        serialization_guard(b, bounds, "max_bytes", parameters),
      )
    }
  }
  { source: at, input, output, profile, sort, max_rows, max_bytes, }
}

///|
/// Resolve the input via existing order owners. Output cardinality one does
/// not establish the serialization input order.
struct SerializationOrder {
  pipeline : CheckedPipeline
  step : Int
  input : Target
  completion : SortCompletion?
  inherited : LogicalOrder?
}

///|
pub fn serialization_order(
  pipeline : CheckedPipeline,
  index : Int,
) -> SerializationOrder? {
  guard pipeline.steps.get(index)
    is Some({ operation: Serialize(_), input: Some(input), .. }) else {
    return None
  }
  let inherited = logical_order(pipeline, input)
  let completion = pipeline.serialization_completions
    .get(index)
    .bind(value => value)
  if completion is None && inherited is None {
    return None
  }
  Some({
    pipeline,
    step: index,
    input,
    completion,
    inherited: if completion is Some(_) {
      None
    } else {
      inherited
    },
  })
}

///|
pub fn serialization_order_pipeline(
  value : SerializationOrder,
) -> CheckedPipeline {
  value.pipeline
}

///|
pub fn serialization_order_input(value : SerializationOrder) -> Target {
  value.input
}

///|
pub fn serialization_order_step(value : SerializationOrder) -> Int {
  value.step
}

///|
pub fn serialization_order_completion(
  value : SerializationOrder,
) -> SortCompletion? {
  value.completion
}

///|
pub fn serialization_order_inherited(
  value : SerializationOrder,
) -> LogicalOrder? {
  value.inherited
}

///|
/// The same stable-sort strategy used by ordinary Relation sorting, scoped to
/// this barrier's input. This is preparation, not physical order fulfillment or
/// evidence about the five-column serialization output.
pub fn serialization_sort_strategy(value : SerializationOrder) -> SortStrategy? {
  guard value.pipeline.steps[value.step].operation is Serialize(checked) &&
    checked.sort is Some(_) else {
    return None
  }
  match (value.completion, value.inherited) {
    (Some(completion), _) => Some(CandidateKey(completion))
    (None, Some(order)) => Some(ExistingTotal(order))
    _ => None
  }
}
