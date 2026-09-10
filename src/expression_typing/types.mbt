///|
/// Object contracts describe complete scopes. None means no supplied scope.
/// Parameters are declarations, never bound values or substituted defaults.
pub(all) struct Environment {
  fields : @contract.Contract?
  left : @contract.Contract?
  right : @contract.Contract?
  parameters : @parameter.Declarations?
}

///|
pub(all) struct Limits {
  max_nodes : Int
  max_depth : Int
  max_work : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  InvalidScope(String)
  UnknownField(String)
  MissingJoinScope(String)
  UnknownParameter(String)
  TypeMismatch(String)
  NullTypeUnresolved
  ForbiddenConstructorValue
  InvalidStaticOption(String)
  BudgetExceeded
} derive(Eq, Debug)

///|
/// Location is in the retained normalized syntax tree, not a fabricated byte
/// mapping through JSON escapes or YAML folding.
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
}

///|
pub(all) enum ObligationKind {
  ProfileAdmission(String)
  PatternValidation(String)
  HostEnvelope
} derive(Eq, Debug)

///|
pub struct Obligation {
  node_index : Int
  kind : ObligationKind
}

///|
/// Includes synthetic CASE ELSE NULL and IN-list element occurrences. The
/// original admitted expression is retained unchanged; these are annotations.
pub struct TypedNode {
  source : @decode.Cursor
  contract : @contract.Contract
  role : AnnotationRole
}

///|
pub(all) enum AnnotationRole {
  ExpressionNode
  MembershipList
  MembershipElement
  ImplicitElse
} derive(Eq, Debug)

///|
struct TypedExpression {
  expression : @syntax.Expression
  environment : Environment
  annotations : Array[TypedNode]
  profiles : Array[String]
  pending : Array[Obligation]
  usage : Usage
}

///|
pub(all) struct Usage {
  work : Int
  text_bytes : Int
  nodes : Int
} derive(Eq, Debug)

///|
pub fn usage(value : TypedExpression) -> Usage {
  value.usage
}

///|
pub fn expression(value : TypedExpression) -> @syntax.Expression {
  value.expression
}

///|
pub fn environment(value : TypedExpression) -> Environment {
  value.environment
}

///|
pub fn result_type(value : TypedExpression) -> @contract.Contract {
  value.annotations[0].contract
}

///|
pub fn node_count(value : TypedExpression) -> Int {
  value.annotations.length()
}

///|
pub fn node_at(value : TypedExpression, index : Int) -> TypedNode? {
  if index < 0 || index >= value.annotations.length() {
    None
  } else {
    Some(value.annotations[index])
  }
}

///|
pub fn required_profiles(value : TypedExpression) -> Array[String] {
  value.profiles.copy()
}

///|
pub fn pending_validations(value : TypedExpression) -> Array[Obligation] {
  value.pending.copy()
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Budget {
  mut work : Int
  mut text : Int
  limits : Limits
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({ source, kind, })
}

///|
fn spend(
  b : Budget,
  source : @decode.Cursor,
  amount? : Int = 1,
) -> Unit raise Stop {
  if amount < 0 || amount > b.work {
    fail(source, BudgetExceeded)
  }
  b.work -= amount
}

///|
fn charge(
  b : Budget,
  source : @decode.Cursor,
  text : String,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(size) => b.text -= size
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
fn[T] decoded(
  result : Result[T, @decode.Issue],
  source : @decode.Cursor,
) -> T raise Stop {
  match result {
    Ok(value) => value
    Err(_) => fail(source, TypeMismatch("admitted syntax"))
  }
}

///|
fn part(body : @decode.Cursor, name : String) -> @decode.Cursor raise Stop {
  let obj = decoded(@decode.open_object(body), body)
  match @decode.lookup(obj, name) {
    Some(value) => value
    None => fail(body, TypeMismatch("admitted member " + name))
  }
}

///|
fn string(body : @decode.Cursor) -> String raise Stop {
  decoded(@decode.text(body), body)
}

///|
priv enum Kind {
  Leaf(@contract.Contract)
  Hole
  Link(Int)
  Sequence(Int, Int64?)
  Product(Array[(String, Int)])
}

///|
priv struct Draft {
  mut kind : Kind
  mut nullable : Bool
  mut complete : @contract.Contract?
  mut height : Int
}

///|
priv struct Types {
  entries : Array[Draft]
  budget : Budget
}

///|
fn put(
  t : Types,
  kind : Kind,
  nullable : Bool,
  source : @decode.Cursor,
) -> Int raise Stop {
  spend(t.budget, source)
  let id = t.entries.length()
  t.entries.push({ kind, nullable, complete: None, height: 0, })
  id
}

///|
fn primitive(
  t : Types,
  p : @contract.Primitive,
  nullable : Bool,
  source : @decode.Cursor,
) -> Int raise Stop {
  put(t, Leaf(@contract.primitive(p, nullable~)), nullable, source)
}

///|
fn head(t : Types, id : Int, source : @decode.Cursor) -> (Int, Bool) raise Stop {
  let mut current = id
  let trail : Array[Int] = []
  while true {
    spend(t.budget, source)
    let d = t.entries[current]
    match d.kind {
      Link(next) => {
        trail.push(current)
        current = next
      }
      _ => {
        let mut nullable = d.nullable
        // Compress evidence aliases while retaining the nullable contribution
        // of every skipped link. Repeated peer lookup does not walk the chain.
        for i = trail.length() - 1; i >= 0; i = i - 1 {
          spend(t.budget, source)
          let link = t.entries[trail[i]]
          nullable = nullable || link.nullable
          link.kind = Link(current)
          link.nullable = nullable
        }
        return (current, nullable)
      }
    }
  }
  fail(source, BudgetExceeded)
}

///|
fn nullability(t : Types, id : Int, source : @decode.Cursor) -> Bool raise Stop {
  head(t, id, source).1
}

///|
fn refine(
  t : Types,
  id : Int,
  nullable : Bool,
  source : @decode.Cursor,
) -> Int raise Stop {
  let (base, _) = head(t, id, source)
  let kind = match t.entries[base].kind {
    Hole => Link(base)
    kind => kind
  }
  put(t, kind, nullable, source)
}

///|
fn reverse_fields(fields : Array[(String, Int)]) -> Unit {
  for i in 0..<(fields.length() / 2) {
    let j = fields.length() - 1 - i
    let saved = fields[i]
    fields[i] = fields[j]
    fields[j] = saved
  }
}

///|
priv enum TypeWork {
  Import(@contract.Contract, Int)
  ArrayEnd(Bool, Int64?)
  ObjectEnd(Bool, Array[String])
}

///|
/// Import once into a flat type arena. Later joins never reparse contracts.
fn import_type(
  t : Types,
  contract : @contract.Contract,
  source : @decode.Cursor,
) -> Int raise Stop {
  let work = [Import(contract, 0)]
  let results : Array[Int] = []
  while work.pop() is Some(task) {
    spend(t.budget, source)
    match task {
      Import(value, depth) => {
        if depth > t.budget.limits.max_depth {
          fail(source, BudgetExceeded)
        }
        match value.shape {
          @contract.Array(item, max_items~) => {
            work.push(ArrayEnd(value.nullable, max_items))
            work.push(Import(item, depth + 1))
          }
          @contract.Object(fields) => {
            let count = @contract.field_count(fields)
            spend(t.budget, source, amount=count)
            let names : Array[String] = []
            for i in 0..<count {
              let field = @contract.field_at(fields, i).unwrap()
              charge(t.budget, source, field.name)
              names.push(field.name)
            }
            work.push(ObjectEnd(value.nullable, names))
            for i = count - 1; i >= 0; i = i - 1 {
              work.push(
                Import(
                  @contract.field_at(fields, i).unwrap().contract,
                  depth + 1,
                ),
              )
            }
          }
          _ => {
            match value.shape {
              @contract.ResourceRef(resource_kind~) =>
                charge(t.budget, source, resource_kind)
              @contract.ArtifactRef(media_type=Some(media)) =>
                charge(t.budget, source, media)
              _ => ()
            }
            let id = put(t, Leaf(value), value.nullable, source)
            t.entries[id].complete = Some(value)
            results.push(id)
          }
        }
      }
      ArrayEnd(nullable, bound) =>
        results.push(
          put(t, Sequence(results.pop().unwrap(), bound), nullable, source),
        )
      ObjectEnd(nullable, names) => {
        let fields : Array[(String, Int)] = []
        for i = names.length() - 1; i >= 0; i = i - 1 {
          fields.push((names[i], results.pop().unwrap()))
        }
        reverse_fields(fields)
        results.push(put(t, Product(fields), nullable, source))
      }
    }
  }
  results[0]
}
