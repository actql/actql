//! Syntax facts only. Cargo/actual Wasm checks provide separate type/ABI evidence.
#![forbid(unsafe_code)]
use anyhow::{Context, Result, ensure};
use quote::ToTokens;
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{collections::{BTreeMap, BTreeSet}, fs, path::{Path, PathBuf}};
use syn::{Item, Visibility, visit::{self, Visit}};

#[derive(Serialize)]
struct Operation {
    name: String,
    parameters: Vec<String>,
    #[serde(rename = "async")]
    is_async: bool,
    declaration: String,
}

#[derive(Serialize)]
pub struct Facts {
    module: String,
    sha256: String,
    exports: Vec<String>,
    operations: Vec<Operation>,
    imports: Vec<String>,
    #[serde(rename = "unresolvedSyntax")]
    unresolved: Vec<String>,
}

fn test_only(attributes: &[syn::Attribute]) -> bool {
    attributes.iter().any(|a| a.path().is_ident("cfg") &&
        a.parse_args::<syn::Path>().is_ok_and(|p| p.is_ident("test")))
}

fn material_attributes(attributes: &[syn::Attribute]) -> String {
    attributes.iter().filter(|attribute| !attribute.path().is_ident("doc"))
        .map(|attribute| attribute.to_token_stream().to_string()).collect::<Vec<_>>().join(" ")
}

struct Reader {
    scope: Vec<String>,
    exports: BTreeSet<String>,
    imports: BTreeSet<String>,
    operations: BTreeMap<String, Operation>,
    children: Vec<(String, Vec<syn::Attribute>)>,
    unresolved: Vec<String>,
}

impl Reader {
    fn new() -> Self {
        Self { scope: vec![], exports: BTreeSet::new(), imports: BTreeSet::new(),
            operations: BTreeMap::new(), children: vec![], unresolved: vec![] }
    }

    fn name(&self, name: &str) -> String {
        self.scope.iter().map(String::as_str).chain([name]).collect::<Vec<_>>().join("/")
    }

    fn export(&mut self, visibility: &Visibility, name: &str) {
        if self.scope.is_empty() && !matches!(visibility, Visibility::Inherited) {
            self.exports.insert(name.to_owned());
        }
    }

    fn signature(&mut self, signature: &syn::Signature, visibility: Option<&Visibility>) {
        let ident = signature.ident.to_string();
        if let Some(visibility) = visibility { self.export(visibility, &ident); }
        let name = self.name(&ident);
        let declaration = format!("{}{}", visibility.map(|v| format!("{} ",v.to_token_stream())).unwrap_or_default(), signature.to_token_stream());
        let parameters = signature.inputs.iter().map(|a| match a {
            syn::FnArg::Receiver(value) => value.to_token_stream().to_string(),
            syn::FnArg::Typed(value) => value.pat.to_token_stream().to_string(),
        }).collect();
        if self.operations.insert(name.clone(), Operation { name, parameters,
            is_async: signature.asyncness.is_some(), declaration }).is_some() {
            self.unresolved.push("Duplicate named operation under conditional/trait syntax".into());
        }
    }

    fn ty(&mut self, ident: &syn::Ident, visibility: &Visibility, declaration: String) {
        self.export(visibility, &ident.to_string());
        let name = self.name(&format!("type:{}",ident));
        if self.operations.insert(name.clone(), Operation { name, parameters: vec![],
            is_async: false, declaration }).is_some() {
            self.unresolved.push("Duplicate named type".into());
        }
    }
}

impl<'ast> Visit<'ast> for Reader {
    fn visit_item(&mut self, item: &'ast Item) {
        let attrs = match item {
            Item::Fn(a) => &a.attrs, Item::Mod(a) => &a.attrs, Item::Impl(a) => &a.attrs,
            Item::Struct(a) => &a.attrs, Item::Enum(a) => &a.attrs, Item::Trait(a) => &a.attrs,
            Item::Type(a) => &a.attrs, Item::Const(a) => &a.attrs, Item::Static(a) => &a.attrs,
            Item::Use(a) => &a.attrs, Item::Macro(a) => &a.attrs,
            _ => { self.unresolved.push("Unsupported Rust item; explicit source-reader support required".into()); return; }
        };
        if test_only(attrs) { return; }
        match item {
            Item::Fn(value) => {
                self.signature(&value.sig,Some(&value.vis));
                self.scope.push(value.sig.ident.to_string());
                self.visit_block(&value.block); self.scope.pop();
            }
            Item::Mod(value) => {
                self.export(&value.vis,&value.ident.to_string());
                if let Some((_,items))=&value.content {
                    self.scope.push(value.ident.to_string());
                    for item in items { self.visit_item(item); } self.scope.pop();
                } else if self.scope.is_empty() {
                    self.children.push((value.ident.to_string(),value.attrs.clone()));
                    self.imports.insert(format!("module:{}",value.ident));
                } else { self.unresolved.push("Out-of-line module nested in inline/function scope".into()); }
            }
            Item::Impl(value) => {
                let owner = format!("impl{}:{}{}",value.generics.to_token_stream(),
                    value.trait_.as_ref().map(|(_,p,_)|format!("{} for ",p.to_token_stream())).unwrap_or_default(),value.self_ty.to_token_stream());
                self.scope.push(owner); visit::visit_item_impl(self,value); self.scope.pop();
            }
            Item::Struct(value) => self.ty(&value.ident,&value.vis,
                format!("{} {} struct {} {} {}", material_attributes(&value.attrs), value.vis.to_token_stream(),value.ident,value.generics.to_token_stream(),value.fields.to_token_stream())),
            Item::Enum(value) => self.ty(&value.ident,&value.vis,
                format!("{} {} enum {} {} {{ {} }}",material_attributes(&value.attrs),value.vis.to_token_stream(),value.ident,value.generics.to_token_stream(),value.variants.to_token_stream())),
            Item::Type(value) => {
                let mut value = value.clone(); value.attrs.retain(|a| !a.path().is_ident("doc"));
                self.ty(&value.ident,&value.vis,value.to_token_stream().to_string());
            },
            Item::Trait(value) => {
                self.export(&value.vis,&value.ident.to_string()); self.scope.push(format!("trait:{}",value.ident));
                visit::visit_item_trait(self,value); self.scope.pop();
            }
            Item::Const(value) => self.export(&value.vis,&value.ident.to_string()),
            Item::Static(value) => self.export(&value.vis,&value.ident.to_string()),
            Item::Use(value) => {
                self.imports.insert(value.tree.to_token_stream().to_string());
                if !matches!(value.vis,Visibility::Inherited) { self.exports.insert(format!("use:{}",value.tree.to_token_stream())); }
            }
            Item::Macro(value) => self.unresolved.push(format!("Unexpanded item macro {}",value.mac.path.to_token_stream())),
            _ => visit::visit_item(self,item),
        }
    }
    fn visit_impl_item_fn(&mut self, value: &'ast syn::ImplItemFn) {
        if test_only(&value.attrs) { return; }
        self.signature(&value.sig,Some(&value.vis)); self.scope.push(value.sig.ident.to_string());
        self.visit_block(&value.block); self.scope.pop();
    }
    fn visit_trait_item_fn(&mut self, value: &'ast syn::TraitItemFn) {
        if test_only(&value.attrs) { return; }
        self.signature(&value.sig,None);
        if let Some(body)=&value.default { self.scope.push(value.sig.ident.to_string()); self.visit_block(body); self.scope.pop(); }
    }
}

fn collect(root: &Path, path: &Path, found: &mut BTreeMap<PathBuf,Facts>) -> Result<()> {
    let path=path.canonicalize().context("Missing Rust module")?;
    ensure!(path.starts_with(root) && path.extension().is_some_and(|p|p=="rs"),"Rust module escapes selected source root");
    ensure!(!found.contains_key(&path) && found.len()<256,"Repeated or excessive Rust module mount");
    let bytes=fs::read(&path)?;ensure!(bytes.len()<=8*1024*1024,"Oversized Rust source module");
    let source=std::str::from_utf8(&bytes)?;let syntax=syn::parse_file(source)?;
    let mut reader=Reader::new();for item in &syntax.items { reader.visit_item(item); }
    let base=if matches!(path.file_name().and_then(|x|x.to_str()),Some("lib.rs"|"main.rs"|"mod.rs")) {
        path.parent().unwrap().to_owned()
    } else { path.parent().unwrap().join(path.file_stem().unwrap()) };
    let children=std::mem::take(&mut reader.children);
    ensure!(reader.unresolved.is_empty(),"Unresolved Rust source syntax: {:?}",reader.unresolved);
    found.insert(path.clone(), Facts { module:path.strip_prefix(root)?.to_str().context("Non-UTF8 Rust source path")?.replace('\\',"/"),
        sha256:format!("{:x}",Sha256::digest(&bytes)),exports:reader.exports.into_iter().collect(),
        operations:reader.operations.into_values().collect(),imports:reader.imports.into_iter().collect(),unresolved:reader.unresolved });
    for (name,attrs) in children {
        let explicit=attrs.iter().find(|a|a.path().is_ident("path"));
        let child=if let Some(attribute)=explicit {
            let syn::Meta::NameValue(value)=&attribute.meta else { anyhow::bail!("Invalid Rust module path attribute"); };
            let syn::Expr::Lit(syn::ExprLit { lit:syn::Lit::Str(value),.. })=&value.value else { anyhow::bail!("Nonliteral Rust module path"); };
            path.parent().unwrap().join(value.value())
        } else {
            let flat=base.join(format!("{name}.rs"));let nested=base.join(&name).join("mod.rs");
            ensure!(flat.is_file()!=nested.is_file(),"Missing or ambiguous Rust module {name}");
            if flat.is_file() { flat } else { nested }
        };
        collect(root,&child,found)?;
    }
    Ok(())
}

pub fn inventory(root: &Path, entry: &Path) -> Result<Vec<Facts>> {
    let root = root.canonicalize()?;
    let mut facts = BTreeMap::new();
    collect(&root, entry, &mut facts)?;
    Ok(facts.into_values().collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn facts(source:&str)->Reader { let mut r=Reader::new();let s=syn::parse_file(source).unwrap();for i in &s.items { r.visit_item(i); }r }
    #[test]
    fn named_operations_preserve_types_receivers_and_skip_only_test_module() {
        let r=facts("pub(crate) struct Token { value: i64 } impl Token { pub fn read(&self, n: u32) -> i64 { n as i64 } } #[cfg(test)] mod tests { fn hidden() {} }");
        assert!(r.exports.contains("Token"));assert_eq!(r.operations.len(),2);
        let op=r.operations.values().find(|v|v.name.ends_with("/read")).unwrap();
        assert_eq!(op.parameters,["& self","n"]);assert!(op.declaration.contains("-> i64"));
        let changed=facts("pub(crate) struct Token { value: i32 } impl Token { pub fn read(&mut self, n: u64) -> i32 { n as i32 } }");
        assert_ne!(op.declaration,changed.operations.values().find(|v|v.name.ends_with("/read")).unwrap().declaration);
        assert_ne!(r.operations["type:Token"].declaration,changed.operations["type:Token"].declaration);
    }
    #[test]
    fn documentation_and_implementation_bodies_are_not_type_contracts() {
        let before=facts("/// old docs\npub struct Token { n: i64 } pub fn read(n: i64) -> i64 { n }");
        let after=facts("/// new docs\npub struct Token { n: i64 } pub fn read(n: i64) -> i64 { n + 1 }");
        assert_eq!(serde_json::to_value(before.operations).unwrap(), serde_json::to_value(after.operations).unwrap());
    }

    #[test]
    fn item_macros_are_unresolved_instead_of_inventing_exports() {
        let r=facts("include!(\"generated.rs\");");assert_eq!(r.unresolved.len(),1);assert!(r.operations.is_empty());
    }
}
