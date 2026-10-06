///|
// Build one ordinary projection for an already resolved star column. This AST
// has no checker/provider authority. Replacement values keep their source tree.
pub fn star_column_projection(
  query : Query,
  projection : Projection,
  column : String,
) -> Projection {
  let name : NamePart = { value: column, quoted: true, }
  for value in projection.replacements {
    if same_cte_name(value.name, name) {
      return {
        expression: value.expression,
        aggregate: value.aggregate,
        analytic: value.analytic,
        name: Some(name),
        star: None,
        except_columns: [],
        replacements: [],
      }
    }
  }
  let path = match projection.expression {
    Some(receiver) =>
      match receiver.nodes[receiver.root].kind {
        Reference(path) => path.copy()
        _ => []
      }
    None => []
  }
  path.push(name)
  // This generated field has no authored token. Its empty span must not
  // pretend that a replacement expression contained that field name.
  let expression : Expression = {
    source: query.source,
    nodes: [{ kind: Reference(path), start: 0, end: 0, }],
    root: 0,
    work: 1,
  }
  {
    expression: Some(expression),
    aggregate: None,
    analytic: None,
    name: Some(name),
    star: None,
    except_columns: [],
    replacements: [],
  }
}
