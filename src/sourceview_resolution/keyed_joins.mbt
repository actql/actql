///|
pub(all) enum KeyedJoinIssueKind {
  InvalidLimits
  WorkLimit
  InconsistentConsumer
  FullJoin(Int)
  UnknownResponseField(Int, String)
  MissingResponseField(Int, String)
} derive(Eq, Debug)

///|
pub struct KeyedJoinIssue {
  kind : KeyedJoinIssueKind
  source : @decode.Cursor?
}

///|
struct KeyedJoin {
  input_index : Int
  step_index : Int
  operation : @join.CheckedJoin
  left : @pipeline.Target
  request : ParameterizedKeyedRequest
  roles : @environment.SourceCorrelation
  pair_roles : Array[Int]
  first : Array[Int]
}

///|
struct CheckedKeyedJoins {
  requests : PipelineRequests
  joins : Array[KeyedJoin]
  work : Int
}

///|
priv suberror KeyedJoinStop {
  KeyedJoinStop(KeyedJoinIssue)
}

///|
fn keyed_join_charge(
  b : Budget,
  n : Int,
  source : @decode.Cursor?,
) -> Unit raise KeyedJoinStop {
  if n > b.work {
    raise KeyedJoinStop({ kind: WorkLimit, source, })
  }
  b.work -= n
}

///|
/// Bind Catalog roles to every actual keyed join. Does not prove request-value
/// validity, completeness, left capacity, response limits or execution support.
pub fn check_keyed_joins(
  requests : PipelineRequests,
  max_work : Int,
) -> Result[CheckedKeyedJoins, KeyedJoinIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let b = { work: max_work, }
  let pipeline = @collection.pipeline(
    @stages.collection(requests.uses.attachment.stage),
  )
  let joins = []
  try {
    keyed_join_charge(b, 1, None)
    for i in 0..<requests.entries.length() {
      keyed_join_charge(b, 1, None)
      if requests.entries[i] is Keyed(_, request) {
        let roles = keyed_request_correlation(request.request)
        let role_count = @environment.source_correlation_pair_count(roles)
        let by_name : Map[String, Int] = Map([])
        for j in 0..<role_count {
          let role = @environment.source_correlation_pair_at(roles, j).unwrap().response
          keyed_join_charge(b, 1, Some(role.source))
          keyed_join_charge(b, role.name.length(), Some(role.source))
          by_name[role.name] = j
        }
        for consumer in requests.uses.entries[i] {
          keyed_join_charge(b, 1, None)
          guard consumer is JoinRight(step_index) else {
            raise KeyedJoinStop({ kind: InconsistentConsumer, source: None, })
          }
          let step = @pipeline.step_at(pipeline, step_index).unwrap()
          guard step.operation is @pipeline.Join(checked=operation, ..) &&
            step.input is Some(left) else {
            raise KeyedJoinStop({
              kind: InconsistentConsumer,
              source: Some(step.source),
            })
          }
          if @join.kind(operation) == @join.Full {
            raise KeyedJoinStop({
              kind: FullJoin(step_index),
              source: Some(@join.source(operation)),
            })
          }
          keyed_join_charge(b, role_count, Some(step.source))
          let first = Array::make(role_count, -1)
          let pair_roles = []
          for j in 0..<@join.key_count(operation) {
            let pair = @join.key_at(operation, j).unwrap()
            let name = @row.reference_name(pair.right)
            keyed_join_charge(b, 1, Some(pair.source))
            keyed_join_charge(b, name.length(), Some(pair.source))
            let role = match by_name.get(name) {
              Some(v) => v
              None =>
                raise KeyedJoinStop({
                  kind: UnknownResponseField(step_index, name),
                  source: Some(pair.source),
                })
            }
            pair_roles.push(role)
            if first[role] == -1 {
              first[role] = j
            }
          }
          for j in 0..<role_count {
            keyed_join_charge(b, 1, Some(step.source))
            if first[j] == -1 {
              let role = @environment.source_correlation_pair_at(roles, j).unwrap().response
              raise KeyedJoinStop({
                kind: MissingResponseField(step_index, role.name),
                source: Some(@join.source(operation)),
              })
            }
          }
          joins.push({
            input_index: i,
            step_index,
            operation,
            left,
            request,
            roles,
            pair_roles,
            first,
          })
        }
      }
    }
    Ok({ requests, joins, work: max_work - b.work, })
  } catch {
    KeyedJoinStop(e) => Err(e)
  }
}

///|
pub fn keyed_joins_requests(v : CheckedKeyedJoins) -> PipelineRequests {
  v.requests
}

///|
pub fn keyed_joins_work(v : CheckedKeyedJoins) -> Int {
  v.work
}

///|
pub fn keyed_join_count(v : CheckedKeyedJoins) -> Int {
  v.joins.length()
}

///|
pub fn keyed_join_at(v : CheckedKeyedJoins, i : Int) -> KeyedJoin? {
  v.joins.get(i)
}

///|
pub fn keyed_join_input(v : KeyedJoin) -> Int {
  v.input_index
}

///|
pub fn keyed_join_step(v : KeyedJoin) -> Int {
  v.step_index
}

///|
pub fn keyed_join_operation(v : KeyedJoin) -> @join.CheckedJoin {
  v.operation
}

///|
pub fn keyed_join_left(v : KeyedJoin) -> @pipeline.Target {
  v.left
}

///|
pub fn keyed_join_request(v : KeyedJoin) -> ParameterizedKeyedRequest {
  v.request
}

///|
pub fn keyed_join_role_at(
  v : KeyedJoin,
  i : Int,
) -> (@environment.CorrelationPair, @join.KeyPair)? {
  v.first
  .get(i)
  .map(j => {
    (
      @environment.source_correlation_pair_at(v.roles, i).unwrap(),
      @join.key_at(v.operation, j).unwrap(),
    )
  })
}

///|
pub fn keyed_join_pair_role(v : KeyedJoin, i : Int) -> Int? {
  v.pair_roles.get(i)
}
