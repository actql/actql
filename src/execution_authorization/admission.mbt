///|
priv struct CompiledEntry {
  entry_id : String
  outcome : ConfiguredOutcome
  scope : Region
  exclusions : Array[Region]
}

///|
/// A configuration whose entries are well formed and whose effective scopes
/// with different outcomes are pairwise disjoint over the open universe.
/// Entries are held in ascending `entry_id` order (lexicographic by UTF-16
/// code unit), so the file order of entries has no semantic effect.
struct AdmittedAccountConfiguration {
  account_id : String
  bootstrap : BootstrapProfile?
  entries : Array[CompiledEntry]
  configuration_cid : String
}

///|
pub fn AdmittedAccountConfiguration::account_id(
  self : AdmittedAccountConfiguration,
) -> String {
  self.account_id
}

///|
/// The bootstrap profile named as provenance by the configuration, if any.
/// It is not evidence of adoption; see `bind_bootstrap_adoption`.
pub fn AdmittedAccountConfiguration::bootstrap_profile(
  self : AdmittedAccountConfiguration,
) -> BootstrapProfile? {
  self.bootstrap
}

///|
pub fn AdmittedAccountConfiguration::configuration_cid(
  self : AdmittedAccountConfiguration,
) -> String {
  self.configuration_cid
}

///|
pub fn AdmittedAccountConfiguration::entry_count(
  self : AdmittedAccountConfiguration,
) -> Int {
  self.entries.length()
}

///|
fn valid_name(value : String) -> Bool {
  value.length() > 0 && value.length() <= MAX_NAME_LENGTH
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
priv suberror AdmissionStop {
  AdmissionStop(ConfigurationIssue)
}

///|
fn compile_selector(
  entry_id : String,
  location : SelectorLocation,
  selector : Selector,
) -> DimSet raise AdmissionStop {
  match selector {
    All => Cofinite([])
    AnyOf(values) => {
      if values.is_empty() {
        raise AdmissionStop(EmptyAnyOf(entry_id, location))
      }
      if values.length() > MAX_SELECTOR_VALUES {
        raise AdmissionStop(SelectorTooLarge(entry_id, location))
      }
      for value in values {
        if !valid_name(value) {
          raise AdmissionStop(InvalidSelectorValue(entry_id, location))
        }
      }
      let sorted = sort_names(values)
      for index in 1..<sorted.length() {
        if sorted[index - 1] == sorted[index] {
          raise AdmissionStop(
            DuplicateSelectorValue(entry_id, location, sorted[index]),
          )
        }
      }
      Finite(sorted)
    }
  }
}

///|
fn compile_box(
  entry_id : String,
  exclusion : Int?,
  box : SelectorBox,
) -> Region raise AdmissionStop {
  let selectors = [box.principal, box.connection, box.resource, box.operation]
  let names = [Principal, Connection, Resource, Operation]
  let dims = FixedArray::make(4, Finite([]))
  for k in 0..<4 {
    let location = match exclusion {
      None => Scope(names[k])
      Some(index) => Exclusion(index, names[k])
    }
    dims[k] = compile_selector(entry_id, location, selectors[k])
  }
  { dims, }
}

///|
fn compile_entry(
  entry : RawAccountEntry,
) -> (CompiledEntry, CanonicalEntry) raise AdmissionStop {
  if entry.exclusions.length() > MAX_EXCLUSIONS_PER_ENTRY {
    raise AdmissionStop(TooManyExclusions(entry.entry_id))
  }
  let scope = compile_box(entry.entry_id, None, entry.scope)
  let keyed : Array[(String, Region, SelectorBox)] = []
  for index, exclusion in entry.exclusions {
    let region = compile_box(entry.entry_id, Some(index), exclusion)
    let text = match box_canonical_text(exclusion) {
      Some(text) => text
      None => raise AdmissionStop(CanonicalDocumentTooLarge)
    }
    keyed.push((text, region, exclusion))
  }
  // Exclusions are a set ordered by their tuples' canonical JSON text.
  keyed.sort_by((left, right) => code_unit_compare(left.0, right.0))
  for index in 1..<keyed.length() {
    if keyed[index - 1].0 == keyed[index].0 {
      raise AdmissionStop(DuplicateExclusion(entry.entry_id, index))
    }
  }
  (
    {
      entry_id: entry.entry_id,
      outcome: entry.outcome,
      scope,
      exclusions: keyed.map(item => item.1),
    },
    {
      entry_id: entry.entry_id,
      outcome: entry.outcome,
      scope: entry.scope,
      exclusions: keyed.map(item => item.2),
    },
  )
}

///|
fn valid_bootstrap_profile(profile : BootstrapProfile) -> Bool {
  valid_name(profile.profile_id) &&
  valid_name(profile.profile_version) &&
  valid_cid(profile.profile_cid)
}

///|
/// Admit a configuration. Every entry must be well formed: non-empty unique
/// entry ids, non-empty `any_of` sets of distinct non-empty values, distinct
/// exclusions, NFC-normalized identifiers, and bounded sizes. A typed
/// configuration may list entries, values and exclusions in any order; the
/// admitted configuration is identified by the CID of its canonical document
/// (`account_configuration_cid`). The JSON decoder additionally requires the
/// canonical order on the wire. Any two entries with different outcomes whose
/// effective scopes (scope minus exclusions) intersect are rejected with a
/// witness tuple, independently of entry order or specificity; no entry is
/// preferred over another. Entries with the same outcome may overlap:
/// evaluation of their common tuples is unambiguous.
pub fn admit_account_configuration(
  raw : RawAccountConfiguration,
) -> Result[AdmittedAccountConfiguration, ConfigurationIssue] {
  admit_with_overlap_budget(raw, MAX_OVERLAP_WORK)
}

///|
fn admit_with_overlap_budget(
  raw : RawAccountConfiguration,
  overlap_steps : Int,
) -> Result[AdmittedAccountConfiguration, ConfigurationIssue] {
  if !valid_name(raw.account_id) {
    return Err(InvalidAccountId)
  }
  match raw.bootstrap {
    Some(profile) =>
      if !valid_bootstrap_profile(profile) {
        return Err(InvalidBootstrapProfile)
      }
    None => ()
  }
  if raw.entries.length() > MAX_ENTRIES {
    return Err(TooManyEntries(raw.entries.length()))
  }
  if first_unnormalized(raw) is Some(path) {
    return Err(NonNormalizedText(path))
  }
  let compiled : Array[(CompiledEntry, CanonicalEntry)] = []
  for index, entry in raw.entries {
    if !valid_name(entry.entry_id) {
      return Err(InvalidEntryId(index))
    }
    compiled.push(compile_entry(entry)) catch {
      AdmissionStop(issue) => return Err(issue)
    }
  }
  compiled.sort_by((left, right) => {
    code_unit_compare(left.0.entry_id, right.0.entry_id)
  })
  let entries = compiled.map(item => item.0)
  for index in 1..<entries.length() {
    if entries[index - 1].entry_id == entries[index].entry_id {
      return Err(DuplicateEntryId(entries[index].entry_id))
    }
  }
  let budget = Ref(overlap_steps)
  for i in 0..<entries.length() {
    for j in (i + 1)..<entries.length() {
      let first = entries[i]
      let second = entries[j]
      if first.outcome == second.outcome {
        continue
      }
      budget.val = budget.val - first.scope.work(second.scope)
      if budget.val < 0 {
        return Err(OverlapCheckBudgetExceeded(first.entry_id, second.entry_id))
      }
      let common = match first.scope.intersect(second.scope) {
        None => continue
        Some(region) => region
      }
      let exclusions = first.exclusions.copy()
      exclusions.push_iter(second.exclusions.iter())
      let found = uncovered_region(common, exclusions, 0, budget) catch {
        OverlapBudgetExhausted =>
          return Err(
            OverlapCheckBudgetExceeded(first.entry_id, second.entry_id),
          )
      }
      match found {
        None => ()
        Some(region) =>
          return Err(
            ConflictingOutcomes({
              first_entry_id: first.entry_id,
              first_outcome: first.outcome,
              second_entry_id: second.entry_id,
              second_outcome: second.outcome,
              witness: region.witness(),
            }),
          )
      }
    }
  }
  let document = canonical_document(
    raw.account_id,
    raw.bootstrap,
    compiled.map(item => item.1),
  )
  let configuration_cid = match document_cid(document) {
    Some(cid) => cid
    None => return Err(CanonicalDocumentTooLarge)
  }
  Ok({
    account_id: raw.account_id,
    bootstrap: raw.bootstrap,
    entries,
    configuration_cid,
  })
}

///|
fn WitnessValue::describe(self : WitnessValue) -> String {
  match self {
    Named(value) => "\"" + value + "\""
    AnyOtherThan([]) => "<any value>"
    AnyOtherThan(values) => {
      let parts = values.map(value => "\"" + value + "\"")
      "<any value other than " + parts.join(", ") + ">"
    }
  }
}

///|
/// A human-readable description of a witness tuple for diagnostics.
pub fn WitnessTuple::describe(self : WitnessTuple) -> String {
  "principal=" +
  self.principal.describe() +
  " connection=" +
  self.connection.describe() +
  " resource=" +
  self.resource.describe() +
  " operation=" +
  self.operation.describe()
}

///|
/// Evaluate one concrete tuple. Cost is O(entries × (1 + exclusions) × log
/// selector size) string comparisons with no allocation. Admission guarantees
/// every matching entry has the same outcome; when several same-outcome
/// entries match, the least `entry_id` (lexicographic by UTF-16 code unit)
/// is reported. No match denies with
/// `NoMatch`, distinct from an explicit deny entry.
pub fn evaluate_account(
  config : AdmittedAccountConfiguration,
  tuple : AccessTuple,
) -> AccountOutcome {
  for entry in config.entries {
    if !entry.scope.contains(tuple) {
      continue
    }
    let mut excluded = false
    for exclusion in entry.exclusions {
      if exclusion.contains(tuple) {
        excluded = true
        break
      }
    }
    if excluded {
      continue
    }
    return match entry.outcome {
      Allow => Allow(entry.entry_id)
      Deny => Deny(Explicit(entry.entry_id))
      Delegate =>
        Delegate({
          account_id: config.account_id,
          entry_id: entry.entry_id,
          tuple,
        })
    }
  }
  Deny(NoMatch)
}

///|
/// The account configuration available to a Host at a boundary. A missing
/// configuration is never treated as allow-all or as first use.
pub(all) enum AccountConfigurationState {
  Missing
  Admitted(AdmittedAccountConfiguration)
}

///|
pub fn evaluate_account_state(
  state : AccountConfigurationState,
  tuple : AccessTuple,
) -> AccountOutcome {
  match state {
    Missing => Deny(ConfigurationMissing)
    Admitted(config) => evaluate_account(config, tuple)
  }
}

///|
/// A Host-supplied durable adoption record for a bootstrap profile. The core
/// neither generates nor persists it.
pub(all) struct BootstrapAdoptionRecord {
  record_id : String
  account_id : String
  profile : BootstrapProfile
} derive(Eq, Debug)

///|
pub(all) enum BootstrapIssue {
  InvalidAdoptionRecord
  ConfigurationWithoutBootstrapProfile
  ProfileMismatch
  AccountMismatch
} derive(Eq, Debug)

///|
/// "Configuration admitted from bootstrap profile X, adopted at record R".
pub struct BootstrappedConfiguration {
  configuration : AdmittedAccountConfiguration
  adoption : BootstrapAdoptionRecord
}

///|
/// Pair an admitted configuration with the Host's adoption record. The
/// configuration must name exactly the adopted profile and account.
pub fn bind_bootstrap_adoption(
  config : AdmittedAccountConfiguration,
  record : BootstrapAdoptionRecord,
) -> Result[BootstrappedConfiguration, BootstrapIssue] {
  if !valid_name(record.record_id) ||
    !valid_name(record.account_id) ||
    !valid_bootstrap_profile(record.profile) {
    return Err(InvalidAdoptionRecord)
  }
  let profile = match config.bootstrap {
    None => return Err(ConfigurationWithoutBootstrapProfile)
    Some(profile) => profile
  }
  if profile != record.profile {
    return Err(ProfileMismatch)
  }
  if config.account_id != record.account_id {
    return Err(AccountMismatch)
  }
  Ok({ configuration: config, adoption: record, })
}
