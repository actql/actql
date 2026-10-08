///|
// Source names bind to admitted declarations. The machine declaration/value
// names remain exact; no value or contract is normalized by this index.
priv struct ParameterNames {
  names : Map[String, String]
  mut work : Int
}

///|
fn query_parameter_names(
  declarations : @parameters.Declarations?,
  max_work : Int,
) -> ParameterNames? raise Abort {
  guard declarations is Some(declarations) else { return None }
  let names : Map[String, String] = Map([])
  let mut work = max_work
  for index in 0..<@parameters.declaration_count(declarations) {
    let name = @parameters.declaration_at(declarations, index).unwrap().name
    let charge = 1 + name.length()
    if charge > work {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
    }
    work -= charge
    let folded = ascii_upper(name)
    if names.contains(folded) {
      // Exact machine declarations may be distinct but cannot define one
      // unambiguous case-insensitive source parameter namespace.
      raise Abort(InvalidContext)
    }
    names[folded] = name
  }
  Some({ names, work, })
}

///|
fn ParameterNames::resolve(
  self : ParameterNames,
  name : String,
) -> Result[String, @expression.Issue] {
  let charge = 1 + name.length()
  if charge > self.work {
    return Err(@expression.WorkLimit)
  }
  self.work -= charge
  // An undeclared name stays undeclared for the ordinary checker. Do not
  // guess a declaration, merge values or provide an implicit default.
  Ok(self.names.get(ascii_upper(name)).unwrap_or(name))
}

///|
fn Construction::parameter_resolver(
  self : Construction,
) -> ((String) -> Result[String, @expression.Issue])? {
  self.parameter_names.map(names => name => names.resolve(name))
}

///|
fn Construction::parameter_text(
  self : Construction,
  name : String,
) -> @builder.Node raise Abort {
  let name = match self.parameter_names {
    None => name
    Some(names) =>
      match names.resolve(name) {
        Ok(name) => name
        Err(issue) =>
          raise Abort(Expression({ issue, origin: Some(self.generated), }))
      }
  }
  self.text(name)
}
