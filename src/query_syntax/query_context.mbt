///|
// Placement is independent of a producer's Carrier and runtime authority.
priv enum QueryContext {
  PureQuery
  ComputeQuery
  StatementQuery
} derive(Eq)

///|
// The first parenthesis is a CTAS Compute wrapper only when its matching close
// ends the input. Inspect the original tokens once; strings and comments cannot
// act as parentheses. Parsing still owns syntax and nesting-depth admission.
fn QueryParser::ctas_whole_wrapper(self : QueryParser) -> Bool raise QueryAbort {
  if self.peek().value != Symbol(40) {
    return false
  }
  let mut depth = 0
  let mut index = self.index
  while index < self.source.tokens.length() {
    self.spend(1)
    let token = self.source.tokens[index]
    match token.value {
      Symbol(40) => depth += 1
      Symbol(41) => {
        depth -= 1
        if depth == 0 {
          let next = token_at(self.source, index + 1)
          return match next {
            Some({ value: End, .. }) => true
            Some({ value: Symbol(59), .. }) => {
              self.spend(1)
              token_at(self.source, index + 2)
              .map(token => token.value == End)
              .unwrap_or(false)
            }
            _ => false
          }
        }
      }
      End => return false
      _ => ()
    }
    index += 1
  }
  false
}
