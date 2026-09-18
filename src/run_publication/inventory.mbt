///|
priv struct PublicationOccurrence {
  task : Int
  definition : ResultDefinition
}

///|
struct CheckedPublicationInventory {
  program_definition_cid : String
  occurrences : Array[PublicationOccurrence]
}

///|
pub(all) enum PublicationInventoryIssue {
  InvalidProgramDefinitionCid
  EmptyInventory
  LengthMismatch
  InvalidTask(Int)
  DuplicateResult(String)
  ResultDefinition(ResultDefinitionIssue)
  InvalidIndex
} derive(Eq, Debug)

///|
/// Construct the complete publication inventory from the checked graph's
/// aligned Result names and producer tasks. No adapter may supply a subset,
/// rename a Result, or mint a Result Definition independently.
pub fn prepare_checked_publication_inventory(
  program_definition_cid : String,
  result_names : Array[String],
  result_tasks : Array[Int],
) -> Result[CheckedPublicationInventory, PublicationInventoryIssue] {
  if !valid_cid(program_definition_cid) {
    return Err(InvalidProgramDefinitionCid)
  }
  if result_names.is_empty() {
    return Err(EmptyInventory)
  }
  if result_names.length() != result_tasks.length() {
    return Err(LengthMismatch)
  }
  let seen : Array[String] = []
  let occurrences : Array[PublicationOccurrence] = []
  for index = 0; index < result_names.length(); index = index + 1 {
    let name = result_names[index]
    if seen.contains(name) {
      return Err(DuplicateResult(name))
    }
    let task = result_tasks[index]
    if task < 0 {
      return Err(InvalidTask(task))
    }
    let definition = match
      prepare_result_definition(program_definition_cid, name) {
      Ok(value) => value
      Err(issue) => return Err(ResultDefinition(issue))
    }
    seen.push(name)
    occurrences.push({ task, definition, })
  }
  Ok({ program_definition_cid, occurrences, })
}

///|
pub fn checked_publication_inventory_program_cid(
  inventory : CheckedPublicationInventory,
) -> String {
  inventory.program_definition_cid
}

///|
pub fn checked_publication_inventory_count(
  inventory : CheckedPublicationInventory,
) -> Int {
  inventory.occurrences.length()
}

///|
fn checked_occurrence(
  inventory : CheckedPublicationInventory,
  index : Int,
) -> Result[PublicationOccurrence, PublicationInventoryIssue] {
  if index < 0 || index >= inventory.occurrences.length() {
    return Err(InvalidIndex)
  }
  Ok(inventory.occurrences[index])
}

///|
pub fn checked_publication_inventory_name(
  inventory : CheckedPublicationInventory,
  index : Int,
) -> Result[String, PublicationInventoryIssue] {
  let occurrence = match checked_occurrence(inventory, index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(result_definition_name(occurrence.definition))
}

///|
pub fn checked_publication_inventory_task(
  inventory : CheckedPublicationInventory,
  index : Int,
) -> Result[Int, PublicationInventoryIssue] {
  let occurrence = match checked_occurrence(inventory, index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(occurrence.task)
}

///|
pub fn checked_publication_inventory_definition_cid(
  inventory : CheckedPublicationInventory,
  index : Int,
) -> Result[String, PublicationInventoryIssue] {
  let occurrence = match checked_occurrence(inventory, index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(result_definition_cid(occurrence.definition))
}

///|
pub fn checked_publication_inventory_definition_json(
  inventory : CheckedPublicationInventory,
  index : Int,
) -> Result[String, PublicationInventoryIssue] {
  let occurrence = match checked_occurrence(inventory, index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match result_definition_json(occurrence.definition) {
    Ok(value) => Ok(value)
    Err(issue) => Err(ResultDefinition(issue))
  }
}
