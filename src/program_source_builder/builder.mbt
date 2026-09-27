///|
pub(all) struct Limits {
  source : @source.ParseLimits
  tree : @wire.Limits
  max_origin_entries : Int
  max_output_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  InputLimit
  Closed
  ForeignNode
  ForeignOrigin
  InvalidSpan
  NodeLimit
  DepthLimit
  StringLimit
  OriginLimit
  OutputLimit
  InvalidScalar
  DuplicateKey(String)
  Admission(@wire.Issue)
} derive(Eq, Debug)

///|
priv suberror Failure {
  Failure(Issue)
}

///|
struct Builder {
  owner : Ref[Unit]
  document : @origin.Document
  limits : Limits
  mut allocated_nodes : Int
  mut allocated_text : Int
  mut origins : Int
  mut closed : Bool
}

///|
priv struct Annotation {
  value : @origin.Origin
  key : @origin.Origin?
}

///|
struct Node {
  owner : Ref[Unit]
  tree : @map.Node[Annotation]
  nodes : Int
  depth : Int
  text_bytes : Int
  output_bytes : Int
  origin_entries : Int
}

///|
pub(all) struct Field {
  key : String
  origin : @origin.Origin
  value : Node
}

///|
/// Children must be immutable nodes issued by this builder. Arrays are copied.
pub(all) enum Value {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[Node])
  Object(Array[Field])
}

///|
struct Source {
  cursor : @wire.Cursor
  origins : @map.Map[Annotation]
  usage : @source.ParseUsage
  output_bytes : Int
}

///|
pub fn create(
  document : @origin.Document,
  limits : Limits,
) -> Result[Builder, Issue] {
  if limits.source.max_input_bytes < 0 ||
    limits.source.max_input_bytes == 2147483647 ||
    limits.source.max_nodes < 0 ||
    limits.source.max_depth < 0 ||
    limits.tree.max_nodes < 0 ||
    limits.tree.max_depth < 0 ||
    limits.tree.max_string_bytes < 0 ||
    limits.tree.max_total_string_bytes < 0 ||
    limits.max_origin_entries < 0 ||
    limits.max_output_bytes < 0 {
    return Err(InvalidLimits)
  }
  if @origin.input_bytes(document) > limits.source.max_input_bytes {
    return Err(InputLimit)
  }
  Ok({
    owner: Ref(()),
    document,
    limits,
    allocated_nodes: 0,
    allocated_text: 0,
    origins: 0,
    closed: false,
  })
}

///|
fn bounded_add(
  value : Int,
  increment : Int,
  limit : Int,
  issue : Issue,
) -> Int raise Failure {
  if increment > limit - value {
    raise Failure(issue)
  }
  value + increment
}

///|
fn normalized(
  builder : Builder,
  text : String,
  remaining : Int,
) -> (String, Int) raise Failure {
  let allowance = builder.limits.tree.max_string_bytes.min(remaining)
  // Bound normalization input as well as its retained output.
  match
    @scalar.admit_utf8_length(
      text,
      builder.limits.source.max_input_bytes.max(allowance),
    ) {
    Err(@scalar.MalformedUtf16(_)) => raise Failure(InvalidScalar)
    Err(_) => raise Failure(StringLimit)
    Ok(_) => ()
  }
  let text = match @canonical.normalize_nfc_lf(text) {
    Ok(text) => text
    Err(_) => raise Failure(InvalidScalar)
  }
  match @scalar.admit_utf8_length(text, allowance) {
    Ok(size) => (text, size)
    Err(_) => raise Failure(StringLimit)
  }
}

///|
fn scalar_size(
  builder : Builder,
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Int raise Failure {
  try {
    let writer = @encode.measuring_writer(builder.limits.max_output_bytes, 1, 0)
    emit(writer)
    @encode.finish_measurement(writer)
  } catch {
    @encode.OutputLimit => raise Failure(OutputLimit)
    _ => raise Failure(InvalidScalar)
  }
}

///|
fn check_origin(
  builder : Builder,
  origin : @origin.Origin,
) -> Unit raise Failure {
  if !@origin.belongs_to(builder.document, origin) {
    raise Failure(ForeignOrigin)
  }
}

///|
fn check_child(builder : Builder, node : Node) -> Unit raise Failure {
  if !physical_equal(builder.owner, node.owner) {
    raise Failure(ForeignNode)
  }
}

///|
fn build(
  builder : Builder,
  value : Value,
  origin : @origin.Origin,
) -> Node raise Failure {
  if builder.closed {
    raise Failure(Closed)
  }
  check_origin(builder, origin)
  let node_limit = builder.limits.source.max_nodes.min(
    builder.limits.tree.max_nodes,
  )
  if builder.allocated_nodes >= node_limit {
    raise Failure(NodeLimit)
  }
  let child_count = match value {
    Array(xs) => xs.length()
    Object(fs) => fs.length()
    _ => 0
  }
  if child_count > node_limit - 1 {
    raise Failure(NodeLimit)
  }
  let origin_charge = match value {
    Object(_) => child_count
    _ => 0
  }
  let new_origins = bounded_add(
    builder.origins,
    1,
    builder.limits.max_origin_entries,
    OriginLimit,
  )
  let new_origins = bounded_add(
    new_origins,
    origin_charge,
    builder.limits.max_origin_entries,
    OriginLimit,
  )
  let mut origin_entries = bounded_add(
    1,
    origin_charge,
    builder.limits.max_origin_entries,
    OriginLimit,
  )
  let mut nodes = 1
  let mut depth = 0
  let mut text_bytes = 0
  let mut own_text = 0
  let mut output_bytes = 0
  let text_limit = builder.limits.tree.max_total_string_bytes
  let output_limit = builder.limits.max_output_bytes
  let depth_limit = builder.limits.source.max_depth.min(
    builder.limits.tree.max_depth,
  )
  let children : Array[@map.Node[Annotation]] = []
  let fields : Array[@map.Field[Annotation]] = []
  let tree_value : @map.Value[Annotation] = match value {
    Null => {
      output_bytes = scalar_size(builder, w => @encode.null_value(w))
      @map.Null
    }
    Bool(b) => {
      output_bytes = scalar_size(builder, w => @encode.bool_value(w, b))
      @map.Bool(b)
    }
    Number(n) => {
      if n == 0.0 && 1.0 / n < 0.0 {
        raise Failure(InvalidScalar)
      }
      output_bytes = scalar_size(builder, w => @encode.number_value(w, n))
      @map.Number(n)
    }
    String(s) => {
      let (s, size) = normalized(
        builder,
        s,
        text_limit - builder.allocated_text,
      )
      text_bytes = size
      own_text = size
      output_bytes = scalar_size(builder, w => @encode.string_value(w, s))
      @map.String(s)
    }
    Array(xs) => {
      if depth_limit == 0 {
        raise Failure(DepthLimit)
      }
      depth = 1
      output_bytes = bounded_add(0, 2, output_limit, OutputLimit)
      for i, child in xs {
        check_child(builder, child)
        origin_entries = bounded_add(
          origin_entries,
          child.origin_entries,
          builder.limits.max_origin_entries,
          OriginLimit,
        )
        nodes = bounded_add(nodes, child.nodes, node_limit, NodeLimit)
        if child.depth >= depth_limit {
          raise Failure(DepthLimit)
        }
        depth = depth.max(child.depth + 1)
        text_bytes = bounded_add(
          text_bytes,
          child.text_bytes,
          text_limit,
          StringLimit,
        )
        if i > 0 {
          output_bytes = bounded_add(output_bytes, 1, output_limit, OutputLimit)
        }
        output_bytes = bounded_add(
          output_bytes,
          child.output_bytes,
          output_limit,
          OutputLimit,
        )
        children.push(child.tree)
      }
      @map.Array(children)
    }
    Object(fs) => {
      if depth_limit == 0 {
        raise Failure(DepthLimit)
      }
      depth = 1
      output_bytes = bounded_add(0, 2, output_limit, OutputLimit)
      let seen = @shape.key_admission()
      for i, field in fs {
        check_origin(builder, field.origin)
        check_child(builder, field.value)
        let remaining = text_limit - builder.allocated_text - own_text
        let (key, size) = normalized(builder, field.key, remaining)
        if !@shape.admit_key(seen, key) {
          raise Failure(DuplicateKey(key))
        }
        own_text = bounded_add(
          own_text,
          size,
          text_limit - builder.allocated_text,
          StringLimit,
        )
        origin_entries = bounded_add(
          origin_entries,
          field.value.origin_entries,
          builder.limits.max_origin_entries,
          OriginLimit,
        )
        nodes = bounded_add(nodes, field.value.nodes, node_limit, NodeLimit)
        if field.value.depth >= depth_limit {
          raise Failure(DepthLimit)
        }
        depth = depth.max(field.value.depth + 1)
        text_bytes = bounded_add(text_bytes, size, text_limit, StringLimit)
        text_bytes = bounded_add(
          text_bytes,
          field.value.text_bytes,
          text_limit,
          StringLimit,
        )
        if i > 0 {
          output_bytes = bounded_add(output_bytes, 1, output_limit, OutputLimit)
        }
        output_bytes = bounded_add(
          output_bytes,
          scalar_size(builder, w => @encode.string_value(w, key)),
          output_limit,
          OutputLimit,
        )
        output_bytes = bounded_add(output_bytes, 1, output_limit, OutputLimit)
        output_bytes = bounded_add(
          output_bytes,
          field.value.output_bytes,
          output_limit,
          OutputLimit,
        )
        fields.push({
          key,
          key_span: @origin.span(field.origin),
          value: {
            ..field.value.tree,
            annotation: {
              value: field.value.tree.annotation.value,
              key: Some(field.origin),
            },
          },
        })
      }
      @map.Object(fields)
    }
  }
  builder.allocated_nodes += 1
  builder.allocated_text += own_text
  builder.origins = new_origins
  {
    owner: builder.owner,
    tree: {
      value: tree_value,
      span: @origin.span(origin),
      annotation: { value: origin, key: None, },
    },
    nodes,
    depth,
    text_bytes,
    output_bytes,
    origin_entries,
  }
}

///|
/// Failure closes this construction session; no partial Source is published.
pub fn add(
  builder : Builder,
  value : Value,
  origin : @origin.Origin,
) -> Result[Node, Issue] {
  Ok(build(builder, value, origin)) catch {
    Failure(issue) => {
      builder.closed = true
      Err(issue)
    }
  }
}

///|
pub fn discard(builder : Builder) -> Unit {
  builder.closed = true
}

///|
/// Common source-map admission owns the final tree and remeasures tree usage.
pub fn finish(builder : Builder, root : Node) -> Result[Source, Issue] {
  if builder.closed {
    return Err(Closed)
  }
  builder.closed = true
  if !physical_equal(builder.owner, root.owner) {
    return Err(ForeignNode)
  }
  match @map.admit(root.tree, builder.limits.tree) {
    Err(issue) => Err(Admission(issue))
    Ok((cursor, origins)) => {
      let measured = @wire.admission_usage(cursor)
      Ok({
        cursor,
        origins,
        usage: {
          input_bytes: @origin.input_bytes(builder.document),
          nodes: measured.nodes,
          depth: measured.depth,
        },
        output_bytes: root.output_bytes,
      })
    }
  }
}

///|
pub fn cursor(source : Source) -> @wire.Cursor {
  source.cursor
}

///|
pub fn origin(source : Source, cursor : @wire.Cursor) -> @origin.Origin? {
  @map.annotation(source.origins, cursor).map(a => a.value)
}

///|
pub fn key_origin(source : Source, cursor : @wire.Cursor) -> @origin.Origin? {
  match @map.annotation(source.origins, cursor) {
    Some(a) => a.key
    None => None
  }
}

///|
pub fn usage(source : Source) -> @source.ParseUsage {
  source.usage
}

///|
pub fn output_bytes(source : Source) -> Int {
  source.output_bytes
}
