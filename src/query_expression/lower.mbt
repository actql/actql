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
  UnsupportedCast
} derive(Debug)

///|
pub(all) struct Diagnostic {
  issue : Issue
  origin : @origin.Origin?
}

///|
/// Closed semantic roles supplied by a checked frontend scope. A macro cannot
/// turn a Graph element into an untyped runtime value.
pub(all) enum MacroValue {
  Field(String)
  Integer(Int)
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
fn Lowering::empty_array_peer(
  self : Lowering,
  target : @query.ArrayElementType,
) -> @builder.Node raise Abort {
  let name = match target {
    Boolean => "boolean"
    String => "string"
    Number => "number"
    Timestamp => "timestamp"
    Json => "json"
    Signed64 => "int64"
  }
  self.form(
    "empty_array",
    self.object([
      (
        "items",
        self.object([
          ("type", self.add(String(name))),
          ("nullable", self.add(Bool(false))),
        ]),
      ),
    ]),
  )
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
  if text.has_prefix("0x") || text.has_prefix("0X") {
    guard @query.exact_integer_literal(text) is Some(value) else {
      raise Abort(InvalidNumber)
    }
    return value.to_double()
  }
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
/// Admit a numeric token already classified by the query lexer. Named
/// operation arguments share SELECT's precision, finite-value and signed-zero
/// rules; they do not interpret the token as a second expression language.
pub fn numeric_literal(text : String) -> Result[Double, Issue] {
  try {
    if text.has_prefix("-") {
      let value = number(text[1:].to_owned())
      if value == 0.0 {
        raise Abort(InvalidNumber)
      }
      Ok(-value)
    } else {
      Ok(number(text))
    }
  } catch {
    Abort(issue) => Err(issue)
  }
}

///|
fn scalar_call(
  path : Array[@query.NamePart],
) -> (String, String, Int, Int) raise Abort {
  // The syntax owner has decoded quoted name parts. Quotation does not change
  // the installed function namespace, overloads or case-insensitive lookup.
  if path.length() == 2 &&
    upper(path[0].value) == "ACTQL" &&
    upper(path[1].value) == "CONCAT" {
    return ("ACTQL.CONCAT", "concat", 1, 2147483647)
  }
  if path.length() != 1 {
    raise Abort(UnsupportedFunction)
  }
  match upper(path[0].value) {
    "VECTOR_SCORE" => ("VECTOR_SCORE", "vector_score", 3, 3)
    "VECTOR_COSINE_SIMILARITY" =>
      ("VECTOR_COSINE_SIMILARITY", "vector_score", 2, 2)
    "VECTOR_INNER_PRODUCT" => ("VECTOR_INNER_PRODUCT", "vector_score", 2, 2)
    "VECTOR_L2_DISTANCE" => ("VECTOR_L2_DISTANCE", "vector_score", 2, 2)
    "VECTOR_CONCAT" => ("VECTOR_CONCAT", "vector_concat", 2, 2147483647)
    "BYTE_LENGTH" | "OCTET_LENGTH" => ("BYTE_LENGTH", "byte_length", 1, 1)
    "UNICODE" => ("UNICODE", "unicode", 1, 1)
    "CHR" => ("CHR", "chr", 1, 1)
    "REVERSE" => ("REVERSE", "reverse", 1, 1)
    "REPEAT" => ("REPEAT", "repeat", 2, 2)
    "TRANSLATE" => ("TRANSLATE", "translate", 3, 3)
    "INSTR" => ("INSTR", "instr", 2, 4)
    "LENGTH" => ("LENGTH", "len", 1, 1)
    "CHAR_LENGTH" | "CHARACTER_LENGTH" => ("CHAR_LENGTH", "len", 1, 1)
    "SQRT" => ("SQRT", "sqrt", 1, 1)
    "CBRT" => ("CBRT", "cbrt", 1, 1)
    "SIN" => ("SIN", "sin", 1, 1)
    "COS" => ("COS", "cos", 1, 1)
    "TAN" => ("TAN", "tan", 1, 1)
    "ASIN" => ("ASIN", "asin", 1, 1)
    "ACOS" => ("ACOS", "acos", 1, 1)
    "ATAN" => ("ATAN", "atan", 1, 1)
    "SINH" => ("SINH", "sinh", 1, 1)
    "COSH" => ("COSH", "cosh", 1, 1)
    "TANH" => ("TANH", "tanh", 1, 1)
    "ASINH" => ("ASINH", "asinh", 1, 1)
    "ACOSH" => ("ACOSH", "acosh", 1, 1)
    "ATANH" => ("ATANH", "atanh", 1, 1)
    "ATAN2" => ("ATAN2", "atan2", 2, 2)
    "POW" | "POWER" => ("POW", "pow", 2, 2)
    "EXP" => ("EXP", "exp", 1, 1)
    "LN" => ("LN", "ln", 1, 1)
    "LOG" => ("LOG", "log", 1, 2)
    "LOG10" => ("LOG10", "log10", 1, 1)
    "ABS" => ("ABS", "abs", 1, 1)
    "SIGN" => ("SIGN", "sign", 1, 1)
    "ROUND" => ("ROUND", "round", 1, 2)
    "TRUNC" => ("TRUNC", "trunc", 1, 2)
    "SAFE_NEGATE" => ("SAFE_NEGATE", "safe_negate", 1, 1)
    "SAFE_DIVIDE" => ("SAFE_DIVIDE", "safe_divide", 2, 2)
    "SAFE_ADD" => ("SAFE_ADD", "safe_add", 2, 2)
    "SAFE_SUBTRACT" => ("SAFE_SUBTRACT", "safe_subtract", 2, 2)
    "SAFE_MULTIPLY" => ("SAFE_MULTIPLY", "safe_multiply", 2, 2)
    "STRPOS" => ("STRPOS", "strpos", 2, 2)
    "DATE_DIFF" => ("DATE_DIFF", "date_diff", 3, 3)
    "DATE_ADD" => ("DATE_ADD", "date_add", 3, 3)
    "DATE_TRUNC" => ("DATE_TRUNC", "date_trunc", 2, 2)
    "TO_NUMBER" => ("TO_NUMBER", "to_number", 1, 1)
    "TO_STRING" => ("TO_STRING", "to_string", 1, 1)
    "TO_BOOLEAN" => ("TO_BOOLEAN", "to_boolean", 1, 1)
    "TO_TIMESTAMP" => ("TO_TIMESTAMP", "to_timestamp", 1, 1)
    "TO_DECIMAL" => ("TO_DECIMAL", "to_decimal", 1, 3)
    "SPLIT" => ("SPLIT", "split", 1, 2)
    "SUBSTR" | "SUBSTRING" => ("SUBSTR", "substring", 2, 3)
    "LEFT" => ("LEFT", "left", 2, 2)
    "RIGHT" => ("RIGHT", "right", 2, 2)
    "LPAD" => ("LPAD", "lpad", 2, 3)
    "RPAD" => ("RPAD", "rpad", 2, 3)
    "CONTAINS" => ("CONTAINS", "contains", 2, 2)
    "STARTS_WITH" => ("STARTS_WITH", "starts_with", 2, 2)
    "ENDS_WITH" => ("ENDS_WITH", "ends_with", 2, 2)
    "FLOOR" => ("FLOOR", "floor", 1, 1)
    "CEIL" | "CEILING" => ("CEIL", "ceil", 1, 1)
    "LOWER" => ("LOWER", "lower", 1, 1)
    "UPPER" => ("UPPER", "upper", 1, 1)
    "TRIM" => ("TRIM", "trim", 1, 2)
    "LTRIM" => ("LTRIM", "ltrim", 1, 2)
    "RTRIM" => ("RTRIM", "rtrim", 1, 2)
    "REPLACE" => ("REPLACE", "replace", 3, 3)
    "GREATEST" => ("GREATEST", "greatest", 1, 2147483647)
    "LEAST" => ("LEAST", "least", 1, 2147483647)
    "COALESCE" => ("COALESCE", "coalesce", 1, 2147483647)
    "IFNULL" => ("IFNULL", "coalesce", 2, 2)
    "IF" => ("IF", "if", 3, 3)
    "NULLIF" => ("NULLIF", "nullif", 2, 2)
    "CONCAT" => ("CONCAT", "concat_strict", 1, 2147483647)
    _ => raise Abort(UnsupportedFunction)
  }
}

///|
// Compare the installed public function, operation and accepted arity using
// the lowering registry. Equal wire operators alone do not establish public
// function identity: LENGTH/CHAR_LENGTH and IFNULL/COALESCE remain distinct.
pub fn same_scalar_function(
  left : Array[@query.NamePart],
  right : Array[@query.NamePart],
  arity? : Int? = None,
) -> Bool {
  try {
    let a = scalar_call(left)
    let b = scalar_call(right)
    if a == b {
      true
    } else {
      // LOG(x) is the documented unary synonym of LN(x). No general
      // lowered-operator fallback may erase public function/arity identity.
      arity == Some(1) &&
      ((a.0 == "LOG" && b.0 == "LN") || (a.0 == "LN" && b.0 == "LOG"))
    }
  } catch {
    Abort(_) => false
  }
}

///|
fn binary_call(op : String) -> (String, Bool) raise Abort {
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
  (name, op == "NOT LIKE")
}

///|
// Use the same operator and polarity contract as lowering. Different spelling
// alone must not prevent reuse of != / <>, and LIKE is not NOT LIKE.
pub fn same_binary_operator(left : String, right : String) -> Bool {
  try binary_call(left) == binary_call(right) catch {
    Abort(_) => false
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
  resolve_parameter? : ((String) -> Result[String, Issue])? = None,
) -> Result[@builder.Node, Diagnostic] {
  append_with_macros(
    ast,
    resolve,
    (_, _) => None,
    builder,
    max_work,
    resolve_parameter~,
  )
}

///|
/// Resolve a column/range prefix through the caller's scope, then use ordinary
/// property expressions. The common checker owns closed-object field typing.
pub fn append_with_properties(
  ast : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  builder : @builder.Builder,
  max_work : Int,
  resolve_parameter? : ((String) -> Result[String, Issue])? = None,
  resolve_row? : ((Array[@query.NamePart]) -> Array[(String, String)]?)? = None,
) -> Result[@builder.Node, Diagnostic] {
  append_resolved(
    ast,
    resolve,
    (_, _) => None,
    builder,
    max_work,
    true,
    resolve_parameter,
    resolve_row,
  )
}

///|
/// Resolve a closed frontend macro before its element reference is lowered.
/// A caller with object-bearing columns can also enable prefix resolution;
/// macro arguments still resolve before ordinary references in the same tree.
pub fn append_with_macros(
  ast : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  resolve_macro : (Array[@query.NamePart], Array[@query.NamePart]) -> MacroValue?,
  builder : @builder.Builder,
  max_work : Int,
  resolve_properties? : Bool = false,
  resolve_parameter? : ((String) -> Result[String, Issue])? = None,
  resolve_row? : ((Array[@query.NamePart]) -> Array[(String, String)]?)? = None,
) -> Result[@builder.Node, Diagnostic] {
  append_resolved(
    ast, resolve, resolve_macro, builder, max_work, resolve_properties, resolve_parameter,
    resolve_row,
  )
}

///|
fn append_resolved(
  ast : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  resolve_macro : (Array[@query.NamePart], Array[@query.NamePart]) -> MacroValue?,
  builder : @builder.Builder,
  max_work : Int,
  resolve_properties : Bool,
  resolve_parameter : ((String) -> Result[String, Issue])?,
  resolve_row : ((Array[@query.NamePart]) -> Array[(String, String)]?)?,
) -> Result[@builder.Node, Diagnostic] {
  if max_work < 0 {
    return Err({ issue: InvalidLimits, origin: None, })
  }
  let count = @query.expression_node_count(ast)
  if count > max_work {
    return Err({ issue: WorkLimit, origin: None, })
  }
  let macro_children : Array[MacroValue?] = Array::make(count, None)
  let macro_calls : Array[Int?] = Array::make(count, None)
  // Classify grouped references once in postorder. Grouping preserves a
  // binding's role; other expressions never become macro arguments. This
  // avoids rescanning a nested argument for every enclosing call.
  let references : Array[Int?] = Array::make(count, None)
  for i in 0..<count {
    let node = @query.expression_node(ast, i).unwrap()
    match node.kind {
      Reference(_) => references[i] = Some(i)
      Parenthesized(child) => references[i] = references[child]
      _ => ()
    }
    guard node.kind is Call(path, args) &&
      args.length() == 1 &&
      references[args[0]] is Some(reference) &&
      @query.expression_node(ast, reference)
      is Some({ kind: Reference(argument), .. }) else {
      continue
    }
    match resolve_macro(path, argument) {
      Some(value) => {
        macro_children[reference] = Some(value)
        macro_calls[i] = Some(reference)
      }
      None => ()
    }
  }
  let nodes : Array[@builder.Node] = []
  let literals : Array[@builder.Node?] = []
  // Grouping preserves an atom's role in the common IN literal array. Keep
  // this classification in the bounded postorder pass rather than reopening
  // the AST or treating arbitrary expression nodes as parameter holes.
  let numbers : Array[Double?] = []
  let strings : Array[String?] = []
  let parameters : Array[Bool] = []
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
      let mut numeric : Double? = None
      let mut text_literal : String? = None
      let mut parameter = false
      let result = match node.kind {
        Null | Boolean(_) | Number(_) | StringLiteral(_) => {
          let raw = lowering.add(
            match node.kind {
              Null => Null
              Boolean(value) => Bool(value)
              Number(text) => {
                let value = number(text)
                numeric = Some(value)
                Number(value)
              }
              StringLiteral(value) => {
                text_literal = Some(value)
                String(value)
              }
              _ => raise Abort(InvalidArguments)
            },
          )
          literal = Some(raw)
          lowering.form("literal", raw)
        }
        JsonLiteral(text) =>
          lowering.form(
            "typed_literal",
            lowering.object([
              ("type", lowering.add(String("json"))),
              ("value", lowering.add(String(text))),
            ]),
          )
        Reference(parts) =>
          match macro_children[i] {
            Some(Field(name)) =>
              lowering.form("field", lowering.add(String(name)))
            Some(Integer(value)) => {
              let raw = lowering.add(Number(value.to_double()))
              literal = Some(raw)
              lowering.form("literal", raw)
            }
            None => {
              let mut length = parts.length()
              let mut name = resolve(parts)
              while name is None && resolve_properties && length > 1 {
                if work >= max_work {
                  raise Abort(WorkLimit)
                }
                work += 1
                length -= 1
                name = resolve(parts[:length].to_owned())
              }
              let mut value = match name {
                Some(name) => lowering.form("field", lowering.add(String(name)))
                None => {
                  guard parts.length() == 1 &&
                    resolve_row.bind(resolver => resolver(parts))
                    is Some(fields) else {
                    raise Abort(UnknownReference)
                  }
                  // The scope supplies only field names and evaluated slots.
                  // Charge construction before appending; the common object
                  // checker/evaluator owns field typing and value demand.
                  if max_work - work < 2 {
                    raise Abort(WorkLimit)
                  }
                  work += 2
                  let properties : Array[(String, @builder.Node)] = []
                  for (property, slot) in fields {
                    if max_work - work < 3 {
                      raise Abort(WorkLimit)
                    }
                    work += 3
                    properties.push(
                      (
                        property,
                        lowering.form("field", lowering.add(String(slot))),
                      ),
                    )
                  }
                  lowering.form("object", lowering.object(properties))
                }
              }
              for part in parts[length:] {
                if work >= max_work {
                  raise Abort(WorkLimit)
                }
                work += 1
                value = lowering.form(
                  "property",
                  lowering.object([
                    ("name", lowering.add(String(part.value))),
                    ("value", value),
                  ]),
                )
              }
              value
            }
          }
        Property(child, name) =>
          lowering.form(
            "property",
            lowering.object([
              ("name", lowering.add(String(name.value))),
              ("value", nodes[child]),
            ]),
          )
        ParameterReference(name) => {
          parameter = true
          let name = match resolve_parameter {
            None => name
            Some(resolve) =>
              match resolve(name) {
                Ok(name) => name
                Err(issue) => raise Abort(issue)
              }
          }
          lowering.form("$param", lowering.add(String(name)))
        }
        Parenthesized(child) => {
          literal = literals[child]
          numeric = numbers[child]
          text_literal = strings[child]
          parameter = parameters[child]
          nodes[child]
        }
        ArrayConstructor(items, target) => {
          let value = lowering.arguments(
            "array",
            items.map(item => nodes[item]),
          )
          match target {
            None => value
            Some(target) => {
              let empty = lowering.empty_array_peer(target)
              if items.is_empty() {
                empty
              } else {
                // The common checker unifies the declared item contract with
                // the actual elements. The common lazy IF evaluates the array
                // once; this is type evidence, never an element CAST.
                lowering.arguments("if", [
                  lowering.form("literal", lowering.add(Bool(true))),
                  value,
                  empty,
                ])
              }
            }
          }
        }
        Unary(op, child) =>
          match op {
            "NOT" => lowering.form("not", nodes[child])
            "+" | "-" =>
              match numbers[child] {
                Some(value) => {
                  if op == "-" && value == 0.0 {
                    raise Abort(InvalidNumber)
                  }
                  let value = if op == "-" { -value } else { value }
                  numeric = Some(value)
                  let raw = lowering.add(Number(value))
                  literal = Some(raw)
                  lowering.form("literal", raw)
                }
                _ if op == "-" => lowering.form("negate", nodes[child])
                _ if op == "+" && literals[child] is None =>
                  // Two type-preserving numeric negations keep the existing
                  // checker signature and reference the operand exactly once.
                  // Dropping the operator would also admit nonnumeric values.
                  lowering.form("negate", lowering.form("negate", nodes[child]))
                _ => raise Abort(InvalidArguments)
              }
            _ => raise Abort(InvalidArguments)
          }
        Binary(op, left, right) => {
          let (name, inverted) = binary_call(op)
          let value = lowering.arguments(name, [nodes[left], nodes[right]])
          if inverted {
            lowering.form("not", value)
          } else {
            value
          }
        }
        Call(path, args) =>
          match macro_calls[i] {
            Some(child) => nodes[child]
            None => {
              let (public_name, name, minimum, maximum) = scalar_call(path)
              if args.length() < minimum || args.length() > maximum {
                raise Abort(InvalidArguments)
              }
              if name == "to_decimal" && args.length() == 1 {
                // The public lookup also lists an omitted-target spelling.
                // This explicit-target connection cannot invent its P/S.
                // Keep that existing implementation frontier, not a new ban.
                raise Abort(UnsupportedFunction)
              }
              if name == "to_decimal" && args.length() != 3 {
                raise Abort(InvalidArguments)
              }
              if name == "date_trunc" &&
                !(strings[args[1]] is Some("ms" | "s" | "m" | "h" | "d")) {
                current = @query.expression_origin(ast, args[1])
                raise Abort(InvalidArguments)
              }
              if (name == "date_diff" || name == "date_add") &&
                !(strings[args[2]] is Some("ms" | "s" | "m" | "h" | "d")) {
                current = @query.expression_origin(ast, args[2])
                raise Abort(InvalidArguments)
              }
              if ["to_number", "to_string", "to_boolean", "to_timestamp"].contains(
                  name,
                ) {
                // These public spellings use the existing Common CAST contract.
                // Preserve the operand subtree and its original Parameter role.
                let target = match name {
                  "to_number" => "number"
                  "to_string" => "string"
                  "to_boolean" => "boolean"
                  "to_timestamp" => "timestamp"
                  _ => raise Abort(UnsupportedFunction)
                }
                lowering.form(
                  "cast",
                  lowering.object([
                    ("value", nodes[args[0]]),
                    (
                      "target",
                      lowering.object([("type", lowering.add(String(target)))]),
                    ),
                  ]),
                )
              } else if name == "to_decimal" {
                // Precision/scale are the existing literal target role, not
                // evaluated operands or inferred properties of the input.
                guard numbers[args[1]] is Some(precision) &&
                  precision >= 1.0 &&
                  precision <= 38.0 &&
                  precision.trunc() == precision else {
                  current = @query.expression_origin(ast, args[1])
                  raise Abort(InvalidArguments)
                }
                guard numbers[args[2]] is Some(scale) &&
                  scale >= 0.0 &&
                  scale <= precision &&
                  scale.trunc() == scale else {
                  current = @query.expression_origin(ast, args[2])
                  raise Abort(InvalidArguments)
                }
                lowering.form(
                  "cast",
                  lowering.object([
                    ("value", nodes[args[0]]),
                    (
                      "target",
                      lowering.object([
                        ("type", lowering.add(String("decimal"))),
                        ("precision", lowering.add(Number(precision))),
                        ("scale", lowering.add(Number(scale))),
                      ]),
                    ),
                  ]),
                )
              } else if name == "date_trunc" {
                // SQL/Pipe has value-first spelling. Only the admitted literal
                // unit moves into the unchanged Common unit-first body.
                lowering.arguments(name, [nodes[args[1]], nodes[args[0]]])
              } else if name == "vector_score" {
                let metric = if public_name == "VECTOR_SCORE" {
                  // Literal role follows transparent grouping in this bounded
                  // postorder pass. Never evaluate a Parameter, field or CASE
                  // to choose an operator metric or fold a data enum's case.
                  match strings[args[2]] {
                    Some(value) if ["cosine", "dot", "l2"].contains(value) =>
                      value
                    _ => {
                      current = @query.expression_origin(ast, args[2])
                      raise Abort(InvalidArguments)
                    }
                  }
                } else {
                  match public_name {
                    "VECTOR_COSINE_SIMILARITY" => "cosine"
                    "VECTOR_INNER_PRODUCT" => "dot"
                    "VECTOR_L2_DISTANCE" => "l2"
                    _ => raise Abort(UnsupportedFunction)
                  }
                }
                let score = lowering.form(
                  "vector_score",
                  lowering.object([
                    ("left", nodes[args[0]]),
                    ("right", nodes[args[1]]),
                    ("metric", lowering.add(String(metric))),
                  ]),
                )
                // The adopted L2 expression is a negative distance score.
                // Preserve VecA typing, input precision, NULL and numeric law;
                // this explicit surface changes only the score direction.
                if public_name == "VECTOR_L2_DISTANCE" {
                  lowering.form("negate", score)
                } else {
                  score
                }
              } else if name == "log" && args.length() == 1 {
                lowering.form("ln", nodes[args[0]])
              } else if name == "ceil" {
                // Finite-number ceiling uses one operand subtree. The numeric
                // zero also supplies ordinary typing for an untyped NULL.
                let zero = lowering.form("literal", lowering.add(Number(0)))
                let negative = lowering.arguments("subtract", [
                  zero,
                  nodes[args[0]],
                ])
                lowering.form("negate", lowering.form("floor", negative))
              } else if name == "substring" {
                let fields = [
                  ("value", nodes[args[0]]),
                  ("start", nodes[args[1]]),
                ]
                if args.get(2) is Some(length) {
                  fields.push(("length", nodes[length]))
                }
                lowering.form(name, lowering.object(fields))
              } else if maximum == 1 ||
                (
                  ["trim", "ltrim", "rtrim", "round", "trunc"].contains(name) &&
                  args.length() == 1
                ) {
                lowering.form(name, nodes[args[0]])
              } else {
                lowering.arguments(name, args.map(i => nodes[i]))
              }
            }
          }
        Predicate(op, args) =>
          if op == "IN UNNEST" || op == "NOT IN UNNEST" {
            // A literal ARRAY spelling has the same scalar atoms as the
            // existing IN list. Preserve order, duplicates and immediate
            // parameter holes; never evaluate an expression to create an atom.
            // General/annotated arrays retain ordinary common admission.
            let mut right = args[1]
            while @query.expression_node(ast, right)
                  is Some({ kind: Parenthesized(child), .. }) {
              if work >= max_work {
                raise Abort(WorkLimit)
              }
              work += 1
              right = child
            }
            let mut values = nodes[args[1]]
            if @query.expression_node(ast, right)
              is Some({ kind: ArrayConstructor(items, None), .. }) {
              let raw : Array[@builder.Node] = []
              let mut atoms = true
              for item in items {
                if work >= max_work {
                  raise Abort(WorkLimit)
                }
                work += 1
                match literals[item] {
                  Some(value) => raw.push(value)
                  None if parameters[item] => raw.push(nodes[item])
                  None => {
                    atoms = false
                    break
                  }
                }
              }
              if atoms {
                values = lowering.form("literal", lowering.add(Array(raw)))
              }
            }
            lowering.arguments(
              if op == "IN UNNEST" {
                "in"
              } else {
                "not_in"
              },
              [nodes[args[0]], values],
            )
          } else if op == "IN" || op == "NOT IN" {
            let items : Array[@builder.Node] = []
            for j in 1..<args.length() {
              match literals[args[j]] {
                Some(raw) => items.push(raw)
                None if parameters[args[j]] => items.push(nodes[args[j]])
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
        Cast(child, target) =>
          match target {
            Array(item) => {
              let mut original = child
              let mut inspecting = true
              while inspecting {
                if work >= max_work {
                  raise Abort(WorkLimit)
                }
                work += 1
                match @query.expression_node(ast, original).unwrap().kind {
                  Parenthesized(inner) => original = inner
                  Null => inspecting = false
                  _ => raise Abort(UnsupportedCast)
                }
              }
              // Common IF supplies a nullable item contract. The selected
              // original NULL branch remains NULL; the empty peer is not run.
              lowering.arguments("if", [
                lowering.form("literal", lowering.add(Bool(false))),
                lowering.empty_array_peer(item),
                nodes[child],
              ])
            }
            _ => {
              let fields = match target {
                Array(_) => raise Abort(UnsupportedCast)
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
      }
      nodes.push(result)
      literals.push(literal)
      numbers.push(numeric)
      strings.push(text_literal)
      parameters.push(parameter)
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
  resolve_parameter? : ((String) -> Result[String, Issue])? = None,
) -> Result[Lowered, Diagnostic] {
  let builder = match
    @builder.create(@query.expression_document(ast), limits.construction) {
    Ok(builder) => builder
    Err(issue) => return Err({ issue: Construction(issue), origin: None, })
  }
  let root = match
    append(ast, resolve, builder, limits.max_work, resolve_parameter~) {
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
