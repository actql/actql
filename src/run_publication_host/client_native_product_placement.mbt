///|
/// Selected package role in the existing formal inventory. No I/O or authority.
pub(all) enum ClientNativeProductPart {
  LauncherProduct
  PlatformProduct
} derive(Eq, Debug)

///|
/// Closed metadata traversal for the exact two package Roots. Physical Roots,
/// funding, release correspondence and current permission remain independent.
struct ClientNativeProductPlacement {
  launcher : ClientNativeProductMembers
  platform : ClientNativeProductMembers
  launcher_root : String
  platform_root : String
  launcher_census : ClientNativeProductCensus
  platform_census : ClientNativeProductCensus
  nested : Bool
}

///|
fn product_placement_root_valid(root : String) -> Bool {
  root.has_prefix("/") &&
  !root.has_suffix("/") &&
  root.length() <= 4096 &&
  !root.contains("\u{0000}") &&
  !root.contains("//") &&
  !root.split("/").any(part => part == "." || part == "..") &&
  @utf8.encode(root).length() <= 4096
}

///|
/// Match the existing Node launcher's hoisted or nested selected dependency.
/// Path comparison alone does not authenticate a namespace or OriginalRoot.
pub fn prepare_client_native_product_placement(
  launcher : ClientNativeProductMembers,
  platform : ClientNativeProductMembers,
  launcher_root : String,
  platform_root : String,
) -> Result[ClientNativeProductPlacement, ClientNativeLocalRuntimeIssue] {
  if launcher.package_name != "actql" ||
    platform.package_name != "@actql/cli-" + launcher.platform ||
    launcher.platform != platform.platform ||
    launcher.source_sha != platform.source_sha ||
    !product_placement_root_valid(launcher_root) ||
    !product_placement_root_valid(platform_root) ||
    !launcher_root.has_suffix("/actql") {
    return Err(InvalidIdentity)
  }
  let sibling = launcher_root[:launcher_root.length() - 6].to_owned() +
    "/@actql/cli-" +
    launcher.platform
  let nested = if platform_root == sibling {
    false
  } else if platform_root ==
    launcher_root + "/node_modules/@actql/cli-" + launcher.platform {
    true
  } else {
    return Err(InvalidIdentity)
  }
  let launcher_census = match product_census_root(launcher) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let platform_census = match product_census_root(platform) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if nested {
    // The route cannot replace a package-owned file or directory. Add only
    // the one selected route; no node_modules subtree is exempted.
    if launcher_census.members.any(entry => entry.name == "node_modules") {
      return Err(InvalidMember)
    }
    match
      product_census_push(
        launcher_census.members,
        "node_modules",
        ProductDirectory,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    product_census_sort(launcher_census.members)
  }
  Ok({
    launcher,
    platform,
    launcher_root,
    platform_root,
    launcher_census,
    platform_census,
    nested,
  })
}

///|
pub fn client_native_product_placement_root(
  value : ClientNativeProductPlacement,
  part : ClientNativeProductPart,
) -> String {
  match part {
    LauncherProduct => value.launcher_root
    PlatformProduct => value.platform_root
  }
}

///|
/// Expected immediate membership only, including both nested-route levels.
/// The platform payload remains its own Root, not a second traversed subtree.
pub fn client_native_product_placement_census(
  value : ClientNativeProductPlacement,
  part : ClientNativeProductPart,
  parent : String,
) -> Result[ClientNativeProductCensus, ClientNativeLocalRuntimeIssue] {
  match part {
    PlatformProduct =>
      if parent.is_empty() {
        Ok(value.platform_census)
      } else {
        client_native_product_census(value.platform, parent)
      }
    LauncherProduct =>
      if parent.is_empty() {
        Ok(value.launcher_census)
      } else if value.nested && parent == "node_modules" {
        Ok({ members: [{ name: "@actql", kind: ProductDirectory, }], })
      } else if value.nested && parent == "node_modules/@actql" {
        Ok({
          members: [
            { name: "cli-" + value.platform.platform, kind: ProductDirectory, },
          ],
        })
      } else {
        client_native_product_census(value.launcher, parent)
      }
  }
}

///|
/// Number of directory Roots the fixed traversal retains for this package.
/// This is an object-count fact, not charged bytes or capacity permission.
pub fn client_native_product_placement_parent_count(
  value : ClientNativeProductPlacement,
  part : ClientNativeProductPart,
) -> Int {
  let census = match part {
    LauncherProduct => value.launcher_census
    PlatformProduct => value.platform_census
  }
  let mut count = 1
  for entry in census.members {
    if entry.kind == ProductDirectory {
      count += 1
    }
  }
  if part == LauncherProduct && value.nested {
    count + 1
  } else {
    count
  }
}

///|
/// Root first, each unique payload parent once, then the exact nested scope.
/// No arbitrary physical enumeration or caller-mutable member Array is used.
pub fn client_native_product_placement_parent_at(
  value : ClientNativeProductPlacement,
  part : ClientNativeProductPart,
  index : Int,
) -> String? {
  if index < 0 {
    return None
  }
  if index == 0 {
    return Some("")
  }
  let census = match part {
    LauncherProduct => value.launcher_census
    PlatformProduct => value.platform_census
  }
  let mut current = 1
  for entry in census.members {
    if entry.kind == ProductDirectory {
      if index == current {
        return Some(entry.name)
      }
      current += 1
    }
  }
  if part == LauncherProduct && value.nested && index == current {
    Some("node_modules/@actql")
  } else {
    None
  }
}
