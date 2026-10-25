///|
/// Bounds for reusing the checker's existing Catalog admission before query
/// name binding. These are preparation bounds, not execution capacity.
pub(all) struct SourceCatalogLimits {
  max_work : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub(all) struct SourceCatalogUsage {
  work : Int
  bytes : Int
  nodes : Int
} derive(Eq, Debug)

///|
// Retain the selected checker and the Catalog owner it actually admitted.
// This handle does not grant read permission or seal a checked Program.
pub struct PreparedSourceCatalog {
  environment : CheckEnvironment
  catalog : @environment.SourceRequestContracts
  references : @environment.CatalogReferences
  usage : SourceCatalogUsage
  depth_limit : Int
  require_reuse : Bool
}

///|
/// Reuse common Catalog interpretation without a second Frontend reader.
/// Source declarations must subsequently be registered against their own
/// admitted Program/Stage. Model, request, capacity and execution checks remain
/// separate; a successful Catalog preparation cannot replace them.
pub fn prepare_source_catalog(
  environment : CheckEnvironment,
  limits : SourceCatalogLimits,
) -> Result[PreparedSourceCatalog, EnvironmentFailure] {
  prepare_source_catalog_with_reader(environment, limits, prepare_environment)
}

///|
/// Share one Catalog admission with an additional consumer's original registry
/// and Catalog bounds. Value contracts and carrier schemas keep their separate
/// Source bounds; a tighter publication limit does not narrow those domains.
pub fn prepare_source_catalog_with_contents_limits(
  environment : CheckEnvironment,
  limits : SourceCatalogLimits,
  contents_limits : @environment.Limits,
) -> Result[PreparedSourceCatalog, EnvironmentFailure] {
  prepare_source_catalog_with_reader(environment, limits, (wire, budget) => {
    prepare_environment_with_contents_limits(
      wire,
      budget,
      Some(contents_limits),
    )
  })
}

///|
fn prepare_source_catalog_with_reader(
  environment : CheckEnvironment,
  limits : SourceCatalogLimits,
  read : (@environment.WireEnvironment, IdentityBudget) -> (
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
  ) raise EnvironmentFailure,
) -> Result[PreparedSourceCatalog, EnvironmentFailure] {
  let budget = IdentityBudget::{
    work: limits.max_work,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  let (catalog, references) = read(environment.wire, budget) catch {
    failure => return Err(failure)
  }
  Ok({
    environment,
    catalog,
    references,
    usage: {
      work: limits.max_work - budget.work,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    },
    depth_limit: limits.max_depth,
    require_reuse: false,
  })
}

///|
// The retained chain proves the same immutable Environment under its original
// bounds. Replay only its aggregate accounting when the current allowance fits.
// A tighter, unproved allowance keeps the existing bounded reader and errors.
fn reuse_source_catalog(
  prepared : PreparedSourceCatalog,
  environment : @environment.WireEnvironment,
  budget : IdentityBudget,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  reuse_source_catalog_with_reader(
    prepared, environment, budget, prepare_environment,
  )
}

///|
fn reuse_source_catalog_with_reader(
  prepared : PreparedSourceCatalog,
  environment : @environment.WireEnvironment,
  budget : IdentityBudget,
  read : (@environment.WireEnvironment, IdentityBudget) -> (
    @environment.SourceRequestContracts,
    @environment.CatalogReferences,
  ) raise EnvironmentFailure,
) -> (@environment.SourceRequestContracts, @environment.CatalogReferences) raise EnvironmentFailure {
  if !physical_equal(prepared.environment.wire, environment) {
    raise ForeignPreparedCatalog
  }
  if !source_catalog_replay_accounting(
      prepared.usage,
      prepared.depth_limit,
      budget,
      prepared.require_reuse,
    ) {
    return read(environment, budget)
  }
  (prepared.catalog, prepared.references)
}

///|
pub fn source_catalog_owner(
  prepared : PreparedSourceCatalog,
) -> CheckEnvironment {
  prepared.environment
}

///|
pub fn source_catalog_contracts(
  prepared : PreparedSourceCatalog,
) -> @environment.SourceRequestContracts {
  prepared.catalog
}

///|
pub fn source_catalog_usage(
  prepared : PreparedSourceCatalog,
) -> SourceCatalogUsage {
  prepared.usage
}

///|
// Keep all four admission dimensions together. In particular depth is the
// original admitted ceiling, not a post-hoc observed depth inferred from usage.
fn source_catalog_replay_fits(
  usage : SourceCatalogUsage,
  depth_limit : Int,
  budget : IdentityBudget,
) -> Bool {
  budget.work >= usage.work &&
  budget.bytes >= usage.bytes &&
  budget.nodes >= usage.nodes &&
  budget.depth >= depth_limit
}

///|
/// Borrow the exact interpreted Catalog without permitting a fresh reader on
/// a later tighter allowance. This creates at most one shallow wrapper record;
/// it neither funds nor retires the shared Catalog. The installation owner must
/// retain its original capacity and lifetime separately from each query.
pub fn require_source_catalog_reuse(
  prepared : PreparedSourceCatalog,
) -> PreparedSourceCatalog {
  if prepared.require_reuse {
    prepared
  } else {
    { ..prepared, require_reuse: true, }
  }
}

///|
/// Nominal interpreted-owner identity, never structural or CID equivalence.
/// Required-reuse wrappers share these exact owners with their original.
pub fn source_catalog_same_original(
  left : PreparedSourceCatalog,
  right : PreparedSourceCatalog,
) -> Bool {
  physical_equal(left.environment, right.environment) &&
  physical_equal(left.catalog, right.catalog) &&
  physical_equal(left.references, right.references)
}

///|
pub fn source_catalog_requires_reuse(prepared : PreparedSourceCatalog) -> Bool {
  prepared.require_reuse
}

///|
/// Minimum replay allowance for this original. The usage values are existing
/// checker accounting, not a retained-memory or execution-capacity quote.
pub fn source_catalog_replay_limits(
  prepared : PreparedSourceCatalog,
) -> SourceCatalogLimits {
  {
    max_work: prepared.usage.work,
    max_bytes: prepared.usage.bytes,
    max_nodes: prepared.usage.nodes,
    max_depth: prepared.depth_limit,
  }
}

///|
// True means the existing owner was charged and may be reused. False preserves
// the legacy fresh-reader path without partially debiting the caller's budget.
fn source_catalog_replay_accounting(
  usage : SourceCatalogUsage,
  depth_limit : Int,
  budget : IdentityBudget,
  require_reuse : Bool,
) -> Bool raise EnvironmentFailure {
  if !source_catalog_replay_fits(usage, depth_limit, budget) {
    if require_reuse {
      raise BudgetExceeded
    }
    return false
  }
  budget.work -= usage.work
  budget.bytes -= usage.bytes
  budget.nodes -= usage.nodes
  true
}

///|
/// Initial Values preparation dependency guard over this exact interpreted
/// Catalog. This does not authorize a fresh interpretation or replace replay.
pub fn source_catalog_closed_values_dependencies(
  prepared : PreparedSourceCatalog,
  max_work : Int,
) -> @environment.ClosedValuesCatalogDependencies? {
  if !@environment.closed_values_policy_shape(prepared.environment.wire) ||
    @environment.source_request_usage(prepared.catalog).2 != 0 ||
    @environment.member_count(
      prepared.environment.wire,
      @environment.SchemaSnapshots,
    ) !=
    0 {
    return None
  }
  @environment.closed_values_catalog_dependencies(prepared.references, max_work)
}
