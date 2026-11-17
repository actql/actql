//! ActQL's generated Core binding and embedded Host implementation.
//!
//! The scalar binding is private implementation material. Driver applications
//! must not manufacture Core handles, authority or recovery outcomes.
#![forbid(unsafe_code)]

mod abi;
mod abi_generated;
mod transfer;
