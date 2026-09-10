///|
pub(all) enum Operation {
  NormalizeGraph
  Degree
  Components
  GraphBounds
} derive(Eq, Debug)

///|
pub(all) enum Direction {
  Incoming
  Outgoing
  Both
} derive(Eq, Debug)

///|
pub(all) enum ComponentKind {
  Weak
  Strong
} derive(Eq, Debug)

///|
pub enum Count {
  Literal(Int64)
  Parameter(String)
}

///|
pub enum Options {
  Normalize
  DegreeOptions(Direction)
  ComponentOptions(ComponentKind, max_output_rows~ : Count?)
  BoundsOptions(max_nodes~ : Count?, max_edges~ : Count?, max_degree~ : Count?)
}

///|
pub(all) enum Obligation {
  ValidateGraphData
  ResolveSgaProfile
  ResolveGraphResources
  ComponentIdentityOrder
  BindPositiveCount(String)
  BindNonnegativeCount(String)
  BoundsReportOrder
  EnforceOutputGuard
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidBody
  Decode(@decode.IssueKind)
  WrongCarrier(@carrier.Kind)
  InvalidCount
  IncompleteGraph
  UnknownDeltaField(String)
  UntypedDeltaField(String)
  InvalidDeltaType
  UnknownConstructionField(String)
  InvalidConstructionIdentity
  InvalidConstructionLabel
  DuplicateConstructionField(String)
  InvalidPropertyStrategy(String)
  UnknownMergeProperty(String)
  IncompatiblePropertyStrategy(String)
  ScopeCollision(String)
  MissingEdgeLabel
  DuplicateMatchField(String)
  UnknownMatchField(String)
  UntypedMatchField(String)
  InvalidName(String)
  ContractMismatch(@alignment.IssueKind)
  UnknownParameter(String)
  IncompatibleParameter(String)
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  path : Array[@decode.PathSegment]
  span : @span.Span
}

///|
pub(all) struct Limits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) struct Usage {
  work : Int
  nodes : Int
  text_bytes : Int
} derive(Eq, Debug)

///|
struct CheckedGraph {
  source : @decode.Cursor
  operation : Operation
  options : Options
  input : @carrier.Carrier
  output : @carrier.Carrier
  pending : Array[Obligation]
  usage : Usage
}

///|
priv struct Budget {
  limits : Limits
  mut work : Int
  mut nodes : Int
  mut text : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] fail(c : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({
    kind,
    path: @decode.cursor_path(c),
    span: @decode.cursor_span(c),
  })
}

///|
fn[T] decoded(result : Result[T, @decode.Issue]) -> T raise Stop {
  match result {
    Ok(v) => v
    Err(e) =>
      raise Stop({ kind: Decode(e.kind), path: e.path.copy(), span: e.span, })
  }
}

///|
fn spend(b : Budget, c : @decode.Cursor, n : Int) -> Unit raise Stop {
  if n > b.work {
    fail(c, BudgetExceeded)
  }
  b.work -= n
}

///|
fn charge(b : Budget, c : @decode.Cursor, text : String) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(c, BudgetExceeded)
  }
}

///|
fn scan(b : Budget, source : @decode.Cursor) -> Unit raise Stop {
  let stack = [(source, 0)]
  while stack.pop() is Some((c, depth)) {
    if b.nodes == 0 {
      fail(c, BudgetExceeded)
    }
    b.nodes -= 1
    spend(b, c, 1)
    match @decode.view(c) {
      TextValue(text) => charge(b, c, text)
      ArrayValue(xs) => {
        if depth >= b.limits.max_depth || xs.length() > b.nodes {
          fail(c, BudgetExceeded)
        }
        for x in xs.rev_iter() {
          stack.push((x, depth + 1))
        }
      }
      ObjectValue(obj) => {
        let keys = decoded(@decode.object_field_names(c))
        if depth >= b.limits.max_depth || keys.length() > b.nodes {
          fail(c, BudgetExceeded)
        }
        for key in keys.rev_iter() {
          charge(b, c, key)
          stack.push((@decode.lookup(obj, key).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn count(
  c : @decode.Cursor,
  parameters : Map[String, @contract.Contract],
  minimum? : Int64 = 1L,
) -> Count raise Stop {
  if @decode.view(c) is NumberValue(number) {
    guard @scalar.read_safe_integer(number) is Some(n) && n >= minimum else {
      fail(c, InvalidCount)
    }
    return Literal(n)
  }
  let object = decoded(@decode.closed_object(c, ["$param"]))
  let name = decoded(@decode.text(decoded(@decode.required(object, "$param"))))
  let ty = match parameters.get(name) {
    Some(c) => c
    None => fail(c, UnknownParameter(name))
  }
  if ty.nullable || !(ty.shape is @contract.Number) {
    fail(c, IncompatibleParameter(name))
  }
  Parameter(name)
}

///|
/// Static checking only; child contracts are admitted and shared, not re-created.
pub fn check(
  operation : Operation,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : Limits,
) -> Result[CheckedGraph, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    if @carrier.kind(input) != @carrier.GraphKind {
      fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let params : Map[String, @contract.Contract] = Map([])
    if parameters is Some(ds) {
      let n = @parameter.declaration_count(ds)
      spend(b, source, n)
      for i in 0..<n {
        let d = @parameter.declaration_at(ds, i).unwrap()
        charge(b, source, d.name)
        params[d.name] = d.parameter_type.contract
      }
    }
    let pending : Array[Obligation] = [
      ValidateGraphData,
      ResolveSgaProfile,
      ResolveGraphResources,
    ]
    let options = match operation {
      NormalizeGraph => {
        if @decode.boolean(source) != Ok(true) {
          fail(source, InvalidBody)
        }
        Normalize
      }
      Degree => {
        let object = decoded(@decode.closed_object(source, ["direction"]))
        let c = decoded(@decode.required(object, "direction"))
        let direction = match decoded(@decode.text(c)) {
          "in" => Incoming
          "out" => Outgoing
          "both" => Both
          _ => fail(c, InvalidBody)
        }
        DegreeOptions(direction)
      }
      Components => {
        let object = decoded(
          @decode.closed_object(source, ["kind", "max_output_rows"]),
        )
        let c = decoded(@decode.required(object, "kind"))
        let kind = match decoded(@decode.text(c)) {
          "weak" => Weak
          "strong" => Strong
          _ => fail(c, InvalidBody)
        }
        let bound = match @decode.lookup(object, "max_output_rows") {
          None => None
          Some(c) => {
            let bound = count(c, params)
            pending.push(EnforceOutputGuard)
            if bound is Parameter(name) {
              pending.push(BindPositiveCount(name))
            }
            Some(bound)
          }
        }
        pending.push(ComponentIdentityOrder)
        ComponentOptions(kind, max_output_rows=bound)
      }
      GraphBounds => {
        let object = decoded(
          @decode.closed_object(source, ["max_nodes", "max_edges", "max_degree"]),
        )
        let bounds : Array[Count?] = []
        for key in ["max_nodes", "max_edges", "max_degree"] {
          bounds.push(
            match @decode.lookup(object, key) {
              None => None
              Some(c) => {
                let bound = count(c, params, minimum=0L)
                if bound is Parameter(name) {
                  pending.push(BindNonnegativeCount(name))
                }
                Some(bound)
              }
            },
          )
        }
        if bounds.all(v => v is None) {
          fail(source, InvalidBody)
        }
        pending.push(BoundsReportOrder)
        BoundsOptions(
          max_nodes=bounds[0],
          max_edges=bounds[1],
          max_degree=bounds[2],
        )
      }
    }
    let output = if operation == NormalizeGraph {
      input
    } else {
      let id = match input {
        @carrier.GraphValue(g) => Some(@carrier.graph_identity(g))
        _ => None
      }
      let number = Some(@contract.primitive(NumberType, nullable=false))
      let fields : Array[(@row.FieldName, @contract.Contract?)] = if operation ==
        Degree {
        [(Unqualified("node"), id), (Unqualified("degree"), number)]
      } else if operation == GraphBounds {
        [
          (
            Unqualified("kind"),
            Some(@contract.primitive(StringType, nullable=false)),
          ),
          (
            Unqualified("node_id"),
            id.map(c => @contract.with_nullability(c, true)),
          ),
          (Unqualified("actual"), number),
          (Unqualified("max"), number),
        ]
      } else {
        [
          (Unqualified("node_id"), id),
          (Unqualified("component_id"), id),
          (Unqualified("component_size"), number),
        ]
      }
      spend(b, source, fields.length())
      for (field, _) in fields {
        charge(b, source, @row.reference_name(field))
      }
      let rows = match
        @carrier.rows(
          fields,
          field_set=Closed,
          max_fields=fields.length(),
          max_name_bytes=limits.max_text_bytes,
        ) {
        Ok(rows) => rows
        Err(_) => fail(source, BudgetExceeded)
      }
      @carrier.relation(rows)
    }
    Ok({
      source,
      operation,
      options,
      input,
      output,
      pending,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn source(value : CheckedGraph) -> @decode.Cursor {
  value.source
}

///|
pub fn operation(value : CheckedGraph) -> Operation {
  value.operation
}

///|
pub fn options(value : CheckedGraph) -> Options {
  value.options
}

///|
pub fn input(value : CheckedGraph) -> @carrier.Carrier {
  value.input
}

///|
pub fn output(value : CheckedGraph) -> @carrier.Carrier {
  value.output
}

///|
pub fn pending_validations(value : CheckedGraph) -> Array[Obligation] {
  value.pending.copy()
}

///|
pub fn usage(value : CheckedGraph) -> Usage {
  value.usage
}
