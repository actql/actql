///|
pub(all) struct Limits {
  construction : @builder.Limits
  expression : @expression.Limits
  max_work : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  WorkLimit
  UnknownReference
  UnsupportedFunction
  InvalidArguments
  InvalidNumber
  Construction(@builder.Issue)
  Admission(@expression.Issue)
} derive(Debug)

///|
pub(all) struct Diagnostic {
  issue : Issue
  origin : @origin.Origin?
}

///|
struct Lowered {
  source : @builder.Source
  expression : @expression.Expression
}

///|
pub fn expression(lowered : Lowered) -> @expression.Expression {
  lowered.expression
}

///|
pub fn source(lowered : Lowered) -> @builder.Source {
  lowered.source
}

///|
priv suberror Abort {
  Abort(Issue)
}

///|
priv struct Lowering {
  builder : @builder.Builder
  origin : @origin.Origin
}

///|
fn Lowering::add(
  self : Lowering,
  value : @builder.Value,
) -> @builder.Node raise Abort {
  match @builder.add(self.builder, value, self.origin) {
    Ok(node) => node
    Err(issue) => raise Abort(Construction(issue))
  }
}

///|
fn Lowering::object(
  self : Lowering,
  fields : Array[(String, @builder.Node)],
) -> @builder.Node raise Abort {
  self.add(
    Object(
      fields.map(pair => { key: pair.0, value: pair.1, origin: self.origin, }),
    ),
  )
}

///|
fn Lowering::form(
  self : Lowering,
  name : String,
  value : @builder.Node,
) -> @builder.Node raise Abort {
  self.object([(name, value)])
}

///|
fn Lowering::arguments(
  self : Lowering,
  name : String,
  args : Array[@builder.Node],
) -> @builder.Node raise Abort {
  self.form(name, self.add(Array(args)))
}

///|
fn upper(value : String) -> String {
  let out = StringBuilder()
  for unit in value {
    let n = unit.to_int()
    out.write_char(
      (if n >= 97 && n <= 122 { n - 32 } else { n }).unsafe_to_char(),
    )
  }
  out.to_string()
}

///|
fn number(text : String) -> Double raise Abort {
  let mut integer = true
  for unit in text {
    if unit == '.' || unit == 'e' || unit == 'E' {
      integer = false
    }
  }
  // Check the integer token's exact magnitude before any binary64 conversion.
  let mut start = 0
  while start + 1 < text.length() && text[start] == '0' {
    start += 1
  }
  let normalized = text[start:].to_owned()
  if integer &&
    (
      normalized.length() > 16 ||
      (normalized.length() == 16 && normalized > "9007199254740991")
    ) {
    raise Abort(InvalidNumber)
  }
  let normalized = if normalized.has_prefix(".") {
    "0" + normalized
  } else {
    normalized
  }
  let normalized = normalized
    .replace(old=".e", new=".0e")
    .replace(old=".E", new=".0E")
  let normalized = if normalized.has_suffix(".") {
    normalized + "0"
  } else {
    normalized
  }
  match
    @source.parse_json(normalized, {
      max_input_bytes: normalized.length(),
      max_nodes: 1,
      max_depth: 0,
    }) {
    Ok({ value: @source.Number(value), .. }) => value
    _ => raise Abort(InvalidNumber)
  }
}

///|
fn scalar_call(path : Array[@query.NamePart]) -> (String, Int, Int) raise Abort {
  if path.any(part => part.quoted) {
    raise Abort(UnsupportedFunction)
  }
  if path.length() == 2 &&
    upper(path[0].value) == "ACTQL" &&
    upper(path[1].value) == "CONCAT" {
    return ("concat", 1, 2147483647)
  }
  if path.length() != 1 {
    raise Abort(UnsupportedFunction)
  }
  match upper(path[0].value) {
    "LENGTH" => ("len", 1, 1)
    "SQRT" => ("sqrt", 1, 1)
    "FLOOR" => ("floor", 1, 1)
    "LOWER" => ("lower", 1, 1)
    "UPPER" => ("upper", 1, 1)
    "TRIM" => ("trim", 1, 1)
    "COALESCE" => ("coalesce", 1, 2147483647)
    "IF" => ("if", 3, 3)
    "NULLIF" => ("nullif", 2, 2)
    "CONCAT" => ("concat_strict", 1, 2147483647)
    _ => raise Abort(UnsupportedFunction)
  }
}

///|
// Append an expression to the caller's Program source owner. Clause lowering
// can share one builder and retain original token origins without printing an
// expression and sending it through another expression parser.
pub fn append(
  ast : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  builder : @builder.Builder,
  max_work : Int,
) -> Result[@builder.Node, Diagnostic] {
  if max_work < 0 {
    return Err({ issue: InvalidLimits, origin: None, })
  }
  let nodes : Array[@builder.Node] = []
  let literals : Array[@builder.Node?] = []
  let mut current : @origin.Origin? = None
  let mut work = 0
  try {
    for i in 0..<@query.expression_node_count(ast) {
      if work >= max_work {
        raise Abort(WorkLimit)
      }
      work += 1
      let node = @query.expression_node(ast, i).unwrap()
      let origin = @query.expression_origin(ast, i).unwrap()
      current = Some(origin)
      let lowering : Lowering = { builder, origin, }
      let mut literal : @builder.Node? = None
      let result = match node.kind {
        Null | Boolean(_) | Number(_) | StringLiteral(_) => {
          let raw = lowering.add(
            match node.kind {
              Null => Null
              Boolean(value) => Bool(value)
              Number(text) => Number(number(text))
              StringLiteral(value) => String(value)
              _ => raise Abort(InvalidArguments)
            },
          )
          literal = Some(raw)
          lowering.form("literal", raw)
        }
        Reference(parts) => {
          let name = match resolve(parts) {
            Some(name) => name
            None => raise Abort(UnknownReference)
          }
          lowering.form("field", lowering.add(String(name)))
        }
        ParameterReference(name) =>
          lowering.form("$param", lowering.add(String(name)))
        Parenthesized(child) => {
          literal = literals[child]
          nodes[child]
        }
        Unary(op, child) =>
          match op {
            "NOT" => lowering.form("not", nodes[child])
            "+" | "-" =>
              match @query.expression_node(ast, child).unwrap().kind {
                Number(text) => {
                  let value = number(text)
                  if op == "-" && value == 0.0 {
                    raise Abort(InvalidNumber)
                  }
                  let raw = lowering.add(
                    Number(if op == "-" { -value } else { value }),
                  )
                  literal = Some(raw)
                  lowering.form("literal", raw)
                }
                _ if op == "-" => lowering.form("negate", nodes[child])
                _ => raise Abort(InvalidArguments)
              }
            _ => raise Abort(InvalidArguments)
          }
        Binary(op, left, right) => {
          let name = match op {
            "+" => "add"
            "-" => "subtract"
            "*" => "multiply"
            "/" => "divide"
            "%" => "modulo"
            "=" => "eq"
            "!=" | "<>" => "neq"
            "<" => "lt"
            "<=" => "lte"
            ">" => "gt"
            ">=" => "gte"
            "AND" => "and"
            "OR" => "or"
            "||" => "concat_strict"
            "LIKE" | "NOT LIKE" => "like"
            _ => raise Abort(InvalidArguments)
          }
          let value = lowering.arguments(name, [nodes[left], nodes[right]])
          if op == "NOT LIKE" {
            lowering.form("not", value)
          } else {
            value
          }
        }
        Call(path, args) => {
          let (name, minimum, maximum) = scalar_call(path)
          if args.length() < minimum || args.length() > maximum {
            raise Abort(InvalidArguments)
          }
          if maximum == 1 {
            lowering.form(name, nodes[args[0]])
          } else {
            lowering.arguments(name, args.map(i => nodes[i]))
          }
        }
        Predicate(op, args) =>
          if op == "IN" || op == "NOT IN" {
            let items : Array[@builder.Node] = []
            for j in 1..<args.length() {
              match literals[args[j]] {
                Some(raw) => items.push(raw)
                None if @query.expression_node(ast, args[j]).unwrap().kind
                  is ParameterReference(_) => items.push(nodes[args[j]])
                None => raise Abort(InvalidArguments)
              }
            }
            let values = lowering.form("literal", lowering.add(Array(items)))
            lowering.arguments(if op == "IN" { "in" } else { "not_in" }, [
              nodes[args[0]],
              values,
            ])
          } else {
            let (name, negated) = match op {
              "BETWEEN" => ("between", false)
              "NOT BETWEEN" => ("between", true)
              "IS DISTINCT FROM" => ("is_distinct_from", false)
              "IS NOT DISTINCT FROM" => ("is_distinct_from", true)
              "IS NULL" => ("is_null", false)
              "IS NOT NULL" => ("is_null", true)
              "IS TRUE" => ("is_true", false)
              "IS NOT TRUE" => ("is_true", true)
              "IS FALSE" => ("is_false", false)
              "IS NOT FALSE" => ("is_false", true)
              "IS UNKNOWN" => ("is_unknown", false)
              "IS NOT UNKNOWN" => ("is_unknown", true)
              _ => raise Abort(InvalidArguments)
            }
            let value = if args.length() == 1 {
              lowering.form(name, nodes[args[0]])
            } else {
              lowering.arguments(name, args.map(i => nodes[i]))
            }
            if negated {
              lowering.form("not", value)
            } else {
              value
            }
          }
        SearchedCase(branches, otherwise) => {
          let values : Array[@builder.Node] = []
          for branch in branches {
            values.push(
              lowering.object([
                ("when", nodes[branch.0]),
                ("then", nodes[branch.1]),
              ]),
            )
          }
          lowering.form(
            "case",
            lowering.object([
              ("when", lowering.add(Array(values))),
              ("else", nodes[otherwise]),
            ]),
          )
        }
        Cast(child, target) => {
          let fields = match target {
            Boolean => [("type", lowering.add(String("boolean")))]
            String => [("type", lowering.add(String("string")))]
            Number => [("type", lowering.add(String("number")))]
            Timestamp => [("type", lowering.add(String("timestamp")))]
            Decimal(precision, scale) =>
              [
                ("type", lowering.add(String("decimal"))),
                ("precision", lowering.add(Number(precision.to_double()))),
                ("scale", lowering.add(Number(scale.to_double()))),
              ]
          }
          lowering.form(
            "cast",
            lowering.object([
              ("value", nodes[child]),
              ("target", lowering.object(fields)),
            ]),
          )
        }
      }
      nodes.push(result)
      literals.push(literal)
    }
    Ok(nodes[@query.expression_root(ast)])
  } catch {
    Abort(issue) => Err({ issue, origin: current, })
  }
}

///|
// Resolution is explicit: never infer a connector, range or property by
// concatenating path spelling. The caller resolves an admitted scope slot.
pub fn lower(
  ast : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  limits : Limits,
) -> Result[Lowered, Diagnostic] {
  let builder = match
    @builder.create(@query.expression_document(ast), limits.construction) {
    Ok(builder) => builder
    Err(issue) => return Err({ issue: Construction(issue), origin: None, })
  }
  let root = match append(ast, resolve, builder, limits.max_work) {
    Ok(root) => root
    Err(error) => {
      @builder.discard(builder)
      return Err(error)
    }
  }
  let source = match @builder.finish(builder, root) {
    Ok(source) => source
    Err(issue) => return Err({ issue: Construction(issue), origin: None, })
  }
  match @expression.admit(@builder.cursor(source), limits.expression) {
    Ok(expression) => Ok({ source, expression, })
    Err(issue) => Err({ issue: Admission(issue), origin: None, })
  }
}
