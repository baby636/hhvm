// Copyright (c) Facebook, Inc. and its affiliates.
//
// This source code is licensed under the MIT license found in the
// LICENSE file in the "hack" directory of this source tree.
//
// @generated SignedSource<<fc09611a1a15f0d9430c4ddd87f82fd1>>
//
// To regenerate this file, run:
//   hphp/hack/src/oxidized_regen.sh

use arena_trait::TrivialDrop;
use no_pos_hash::NoPosHash;
use ocamlrep_derive::FromOcamlRep;
use ocamlrep_derive::FromOcamlRepIn;
use ocamlrep_derive::ToOcamlRep;
use serde::Deserialize;
use serde::Serialize;

#[allow(unused_imports)]
use crate::*;

pub use typing_defs_flags::*;

pub use typing_defs_core::*;

/// Origin of Class Constant References:
/// In order to be able to detect cycle definitions like
/// class C {
/// const int A = D::A;
/// }
/// class D {
/// const int A = C::A;
/// }
/// we need to remember which constants were used during initialization.
///
/// Currently the syntax of constants allows direct references to another class
/// like D::A, or self references using self::A.
///
/// class_const_from encodes the origin (class vs self).
#[derive(
    Clone,
    Copy,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub enum ClassConstFrom<'a> {
    Self_,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    From(&'a str),
}
impl<'a> TrivialDrop for ClassConstFrom<'a> {}
arena_deserializer::impl_deserialize_in_arena!(ClassConstFrom<'arena>);

/// Class Constant References:
/// In order to be able to detect cycle definitions like
/// class C {
/// const int A = D::A;
/// }
/// class D {
/// const int A = C::A;
/// }
/// we need to remember which constants were used during initialization.
///
/// Currently the syntax of constants allows direct references to another class
/// like D::A, or self references using self::A.
#[derive(
    Clone,
    Copy,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct ClassConstRef<'a>(
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)] pub ClassConstFrom<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)] pub &'a str,
);
impl<'a> TrivialDrop for ClassConstRef<'a> {}
arena_deserializer::impl_deserialize_in_arena!(ClassConstRef<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct ConstDecl<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub pos: &'a pos_or_decl::PosOrDecl<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub type_: &'a Ty<'a>,
}
impl<'a> TrivialDrop for ConstDecl<'a> {}
arena_deserializer::impl_deserialize_in_arena!(ConstDecl<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct ClassElt<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub visibility: CeVisibility<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub type_: &'a lazy::Lazy<&'a Ty<'a>>,
    /// identifies the class from which this elt originates
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub origin: &'a str,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub deprecated: Option<&'a str>,
    /// pos of the type of the elt
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub pos: &'a lazy::Lazy<&'a pos_or_decl::PosOrDecl<'a>>,
    pub flags: isize,
}
impl<'a> TrivialDrop for ClassElt<'a> {}
arena_deserializer::impl_deserialize_in_arena!(ClassElt<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct FunElt<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub deprecated: Option<&'a str>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub type_: &'a Ty<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub pos: &'a pos_or_decl::PosOrDecl<'a>,
    pub php_std_lib: bool,
    pub support_dynamic_type: bool,
}
impl<'a> TrivialDrop for FunElt<'a> {}
arena_deserializer::impl_deserialize_in_arena!(FunElt<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct ClassConst<'a> {
    pub synthesized: bool,
    pub abstract_: bool,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub pos: &'a pos_or_decl::PosOrDecl<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub type_: &'a Ty<'a>,
    /// identifies the class from which this const originates
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub origin: &'a str,
    /// references to the constants used in the initializer
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub refs: &'a [ClassConstRef<'a>],
}
impl<'a> TrivialDrop for ClassConst<'a> {}
arena_deserializer::impl_deserialize_in_arena!(ClassConst<'arena>);

#[derive(
    Clone,
    Copy,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRep,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub enum RecordFieldReq {
    ValueRequired,
    HasDefaultValue,
}
impl TrivialDrop for RecordFieldReq {}
arena_deserializer::impl_deserialize_in_arena!(RecordFieldReq);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct RecordDefType<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub name: PosId<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub extends: Option<PosId<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub fields: &'a [(PosId<'a>, RecordFieldReq)],
    pub abstract_: bool,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub pos: &'a pos_or_decl::PosOrDecl<'a>,
}
impl<'a> TrivialDrop for RecordDefType<'a> {}
arena_deserializer::impl_deserialize_in_arena!(RecordDefType<'arena>);

/// The position is that of the hint in the `use` / `implements` AST node
/// that causes a class to have this requirement applied to it. E.g.
///
/// ```
/// class Foo {}
///
/// interface Bar {
///   require extends Foo; <- position of the decl_phase ty
/// }
///
/// class Baz extends Foo implements Bar { <- position of the `implements`
/// }
/// ```
#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct Requirement<'a>(
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub  &'a pos_or_decl::PosOrDecl<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)] pub &'a Ty<'a>,
);
impl<'a> TrivialDrop for Requirement<'a> {}
arena_deserializer::impl_deserialize_in_arena!(Requirement<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct ClassType<'a> {
    pub need_init: bool,
    /// Whether the typechecker knows of all (non-interface) ancestors
    /// and thus knows all accessible members of this class
    /// This is not the case if one ancestor at least could not be found.
    pub members_fully_known: bool,
    pub abstract_: bool,
    pub final_: bool,
    pub const_: bool,
    /// When a class is abstract (or in a trait) the initialization of
    /// a protected member can be delayed
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub deferred_init_members: s_set::SSet<'a>,
    pub kind: oxidized::ast_defs::ClassKind,
    pub is_xhp: bool,
    pub has_xhp_keyword: bool,
    pub is_disposable: bool,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub name: &'a str,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub pos: &'a pos_or_decl::PosOrDecl<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub tparams: &'a [&'a Tparam<'a>],
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub where_constraints: &'a [&'a WhereConstraint<'a>],
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub consts: s_map::SMap<'a, &'a ClassConst<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub typeconsts: s_map::SMap<'a, &'a TypeconstType<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub props: s_map::SMap<'a, &'a ClassElt<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub sprops: s_map::SMap<'a, &'a ClassElt<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub methods: s_map::SMap<'a, &'a ClassElt<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub smethods: s_map::SMap<'a, &'a ClassElt<'a>>,
    /// the consistent_kind represents final constructor or __ConsistentConstruct
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub construct: (Option<&'a ClassElt<'a>>, ConsistentKind),
    /// This includes all the classes, interfaces and traits this class is
    /// using.
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub ancestors: s_map::SMap<'a, &'a Ty<'a>>,
    /// Whether the class is coercible to dynamic
    pub support_dynamic_type: bool,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub req_ancestors: &'a [&'a Requirement<'a>],
    /// the extends of req_ancestors
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub req_ancestors_extends: s_set::SSet<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub extends: s_set::SSet<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub enum_type: Option<&'a EnumType<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub sealed_whitelist: Option<s_set::SSet<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub xhp_enum_values: s_map::SMap<'a, &'a [ast_defs::XhpEnumValue<'a>]>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub decl_errors: Option<&'a errors::Errors<'a>>,
}
impl<'a> TrivialDrop for ClassType<'a> {}
arena_deserializer::impl_deserialize_in_arena!(ClassType<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct AbstractTypeconst<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub as_constraint: Option<&'a Ty<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub super_constraint: Option<&'a Ty<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub default: Option<&'a Ty<'a>>,
}
impl<'a> TrivialDrop for AbstractTypeconst<'a> {}
arena_deserializer::impl_deserialize_in_arena!(AbstractTypeconst<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct ConcreteTypeconst<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub tc_type: &'a Ty<'a>,
}
impl<'a> TrivialDrop for ConcreteTypeconst<'a> {}
arena_deserializer::impl_deserialize_in_arena!(ConcreteTypeconst<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct PartiallyAbstractTypeconst<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub constraint: &'a Ty<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub type_: &'a Ty<'a>,
}
impl<'a> TrivialDrop for PartiallyAbstractTypeconst<'a> {}
arena_deserializer::impl_deserialize_in_arena!(PartiallyAbstractTypeconst<'arena>);

#[derive(
    Clone,
    Copy,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub enum Typeconst<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    TCAbstract(&'a AbstractTypeconst<'a>),
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    TCConcrete(&'a ConcreteTypeconst<'a>),
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    TCPartiallyAbstract(&'a PartiallyAbstractTypeconst<'a>),
}
impl<'a> TrivialDrop for Typeconst<'a> {}
arena_deserializer::impl_deserialize_in_arena!(Typeconst<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct TypeconstType<'a> {
    pub synthesized: bool,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub name: PosId<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub kind: Typeconst<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub origin: &'a str,
    /// If the typeconst had the <<__Enforceable>> attribute on its
    /// declaration, this will be [(position_of_declaration, true)].
    ///
    /// In legacy decl, the second element of the tuple will also be true if
    /// the typeconst overrides some parent typeconst which had the
    /// <<__Enforceable>> attribute. In that case, the position will point to
    /// the declaration of the parent typeconst.
    ///
    /// In shallow decl, this is not the case--there is no overriding behavior
    /// modeled here, and the second element will only be true when the
    /// declaration of this typeconst had the attribute.
    ///
    /// When the second element of the tuple is false, the position will be
    /// [Pos_or_decl.none].
    ///
    /// To manage the difference between legacy and shallow decl, use
    /// [Typing_classes_heap.Api.get_typeconst_enforceability] rather than
    /// accessing this field directly.
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub enforceable: (&'a pos_or_decl::PosOrDecl<'a>, bool),
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub reifiable: Option<&'a pos_or_decl::PosOrDecl<'a>>,
    pub concretized: bool,
    pub is_ctx: bool,
}
impl<'a> TrivialDrop for TypeconstType<'a> {}
arena_deserializer::impl_deserialize_in_arena!(TypeconstType<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct EnumType<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub base: &'a Ty<'a>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub constraint: Option<&'a Ty<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub includes: &'a [&'a Ty<'a>],
    pub enum_class: bool,
}
impl<'a> TrivialDrop for EnumType<'a> {}
arena_deserializer::impl_deserialize_in_arena!(EnumType<'arena>);

#[derive(
    Clone,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub struct TypedefType<'a> {
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub pos: &'a pos_or_decl::PosOrDecl<'a>,
    pub vis: oxidized::aast::TypedefVisibility,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub tparams: &'a [&'a Tparam<'a>],
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub constraint: Option<&'a Ty<'a>>,
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    pub type_: &'a Ty<'a>,
}
impl<'a> TrivialDrop for TypedefType<'a> {}
arena_deserializer::impl_deserialize_in_arena!(TypedefType<'arena>);

#[derive(
    Clone,
    Copy,
    Debug,
    Deserialize,
    Eq,
    FromOcamlRepIn,
    Hash,
    NoPosHash,
    Ord,
    PartialEq,
    PartialOrd,
    Serialize,
    ToOcamlRep
)]
pub enum DeserializationError<'a> {
    /// The type was valid, but some component thereof was a decl_ty when we
    /// expected a locl_phase ty, or vice versa.
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    WrongPhase(&'a str),
    /// The specific type or some component thereof is not one that we support
    /// deserializing, usually because not enough information was serialized to be
    /// able to deserialize it again.
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    NotSupported(&'a str),
    /// The input JSON was invalid for some reason.
    #[serde(deserialize_with = "arena_deserializer::arena", borrow)]
    DeserializationError(&'a str),
}
impl<'a> TrivialDrop for DeserializationError<'a> {}
arena_deserializer::impl_deserialize_in_arena!(DeserializationError<'arena>);
