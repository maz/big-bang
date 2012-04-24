{-# LANGUAGE FlexibleInstances, EmptyDataDecls, GADTs, StandaloneDeriving #-}
module Language.TinyBang.Ast
( Expr(..)
, Modifier(..)
, Chi(..)
, ChiMain
, ChiStruct
, ChiBind
, ChiPrimary
, ChiMainType
, ChiStructType
, ChiBindType
, ChiPrimaryType
, Branches
, Branch(..)
, Value(..)
-- Re-exported for convenience
, LazyOperator(..)
, EagerOperator(..)
, ProjTerm(..)
, Assignable(..)
, Evaluated(..)
, CellId
, ePatVars
, exprVars
, exprFreeVars
) where

import Data.IntMap (IntMap)
import qualified Data.IntMap as IntMap
import Data.Set (Set)
import qualified Data.Set as Set

import Language.TinyBang.Types.UtilTypes
  ( LabelName
  , Ident
  , unIdent
  , unLabelName
  , LazyOperator(..)
  , EagerOperator(..)
  , ProjTerm(..)
  )
import qualified Language.TinyBang.Types.UtilTypes as T
  ( PrimitiveType(..) )
import Utils.Render.Display

-------------------------------------------------------------------------------

type CellId = Int

-- |Data type for representing Big Bang ASTs.
data Expr
  = Var Ident
  | Label LabelName (Maybe Modifier) Expr
  | Onion Expr Expr
  | OnionSub Expr ProjTerm
  | OnionProj Expr ProjTerm
  | EmptyOnion
  | Func Ident Expr
  | Appl Expr Expr
  | PrimInt Integer
  | PrimChar Char
  | PrimUnit
  | Case Expr Branches
  | Def (Maybe Modifier) Ident Expr Expr
  | Assign Assignable Expr Expr
  | LazyOp LazyOperator Expr Expr
  | EagerOp EagerOperator Expr Expr
  | ExprCell CellId
  deriving (Eq, Ord, Show)

data Modifier
  = Final
  | Immutable
  deriving (Eq, Ord, Show, Enum)

-- |Data type for representing Big Bang values
data Value
  = VLabel LabelName CellId
  | VOnion Value Value
  | VFunc Ident Expr
  | VPrimInt Integer
  | VPrimChar Char
  | VPrimUnit
  | VEmptyOnion
  deriving (Eq, Ord, Show)

data Assignable = ACell CellId | AIdent Ident
  deriving (Eq, Ord, Show)


-- TODO: fix this boilerplate using -XDataKinds in ghc 7.4
data ChiMainType
data ChiStructType
data ChiBindType
data ChiPrimaryType

type ChiMain = Chi ChiMainType
type ChiStruct = Chi ChiStructType
type ChiBind = Chi ChiBindType
type ChiPrimary = Chi ChiPrimaryType

-- |Data type describing top level type patterns in case expressions;
--  corresponds to chi in the document.
data Chi a where
  ChiTopVar       :: Ident                   -> ChiMain
  ChiTopOnion     :: ChiPrimary -> ChiStruct -> ChiMain
  ChiTopBind      :: ChiBind                 -> ChiMain

  ChiOnionMany    :: ChiPrimary -> ChiStruct -> ChiStruct
  ChiOnionOne     :: ChiPrimary              -> ChiStruct

  ChiBound        :: Ident -> ChiBind -> ChiBind
  ChiUnbound      :: ChiPrimary       -> ChiBind

  ChiPrim         :: T.PrimitiveType                -> ChiPrimary
  ChiLabelShallow :: LabelName       -> Ident       -> ChiPrimary
  ChiLabelDeep    :: LabelName       -> ChiBind     -> ChiPrimary
  ChiFun          ::                                   ChiPrimary
  ChiInnerStruct  :: ChiStruct                      -> ChiPrimary

deriving instance Show (Chi a)
deriving instance Eq (Chi a)
deriving instance Ord (Chi a)

-- |Alias for case branches
type Branches = [Branch]
data Branch = Branch ChiMain Expr
  deriving (Eq, Ord, Show)

-- TODO: refactor the pattern stuff into its own module?
-- |Obtains the set of bound variables in a pattern.
ePatVars :: Chi a -> Set Ident
ePatVars chi =
  case chi of
    ChiTopVar x -> Set.singleton x
    ChiTopOnion p s -> both p s
    ChiTopBind b -> ePatVars b
    ChiOnionMany p s -> both p s
    ChiOnionOne p -> ePatVars p
    ChiBound i b -> Set.insert i $ ePatVars b
    ChiUnbound p -> ePatVars p
    ChiPrim _ -> Set.empty
    ChiLabelShallow _ x -> Set.singleton x
    ChiLabelDeep _ b -> ePatVars b
    ChiFun -> Set.empty
    ChiInnerStruct s -> ePatVars s
  where both :: Chi a -> Chi b -> Set Ident
        both x y = Set.union (ePatVars y) (ePatVars x)

-- |Obtains the set of free variables for a given expression.
exprFreeVars :: Expr -> Set Ident
exprFreeVars e =
  case e of
    Var i -> Set.singleton i
    Label _ _ e' -> exprFreeVars e'
    Onion e1 e2 -> exprFreeVars e1 `Set.union` exprFreeVars e2
    OnionProj e' _ -> exprFreeVars e'
    OnionSub e' _ -> exprFreeVars e'
    Func i e' -> i `Set.delete` exprFreeVars e'
    Appl e1 e2 -> exprFreeVars e1 `Set.union` exprFreeVars e2
    PrimInt _ -> Set.empty
    PrimChar _ -> Set.empty
    PrimUnit -> Set.empty
    Case e' brs -> Set.union (exprFreeVars e') $ Set.unions $
      map (\(Branch chi e'') ->
              exprFreeVars e'' `Set.difference` ePatVars chi) brs
    EmptyOnion -> Set.empty
    LazyOp _ e1 e2 -> exprFreeVars e1 `Set.union` exprFreeVars e2
    EagerOp _ e1 e2 -> exprFreeVars e1 `Set.union` exprFreeVars e2
    Def _ i e1 e2 ->
      (i `Set.delete` exprFreeVars e2) `Set.union` exprFreeVars e1
    Assign a e1 e2 ->
        ((case a of
            AIdent i -> (Set.delete i)
            ACell _ -> id) $ exprFreeVars e2)
          `Set.union` exprFreeVars e1
    ExprCell _ -> Set.empty

-- |Obtains the set of all variables in a given expression.  This includes the
--  variables found in patterns and other constructs.
exprVars :: Expr -> Set Ident
exprVars e =
  case e of
    Var i -> Set.singleton i
    Label _ _ e' -> exprVars e'
    Onion e1 e2 -> exprVars e1 `Set.union` exprVars e2
    OnionProj e' _ -> exprVars e'
    OnionSub e' _ -> exprVars e'
    Func i e' -> i `Set.insert` exprVars e'
    Appl e1 e2 -> exprVars e1 `Set.union` exprVars e2
    PrimInt _ -> Set.empty
    PrimChar _ -> Set.empty
    PrimUnit -> Set.empty
    Case e' brs -> Set.union (exprVars e') $ Set.unions $
      map (\(Branch chi e'') ->
              exprVars e'' `Set.difference` ePatVars chi) brs
    EmptyOnion -> Set.empty
    LazyOp _ e1 e2 -> exprVars e1 `Set.union` exprVars e2
    EagerOp _ e1 e2 -> exprVars e1 `Set.union` exprVars e2
    Def _ i e1 e2 -> (i `Set.insert` exprVars e1) `Set.union` exprVars e2
    Assign a e1 e2 -> (case a of
                        AIdent i -> Set.insert i
                        ACell _ -> id) $ exprVars e1 `Set.union` exprVars e2
    ExprCell _ -> Set.empty

instance Display Expr where
  makeDoc a = case a of
    Var i -> text $ unIdent i
    Label n m e ->
      char '`' <> (text $ unLabelName n) <+> dispMod m <+> (parens $ makeDoc e)
    Onion e1 e2 -> makeDoc e1 <+> char '&' <+> makeDoc e2
    Func i e -> parens $
            text "fun" <+> (text $ unIdent i) <+> text "->" <+> makeDoc e
    Appl e1 e2 -> parens $ makeDoc e1 <+> makeDoc e2
    PrimInt i -> integer i
    PrimChar c -> quotes $ char c
    PrimUnit -> parens empty
    Case e brs -> parens $ text "case" <+> (parens $ makeDoc e) <+> text "of"
            <+> text "{" $+$
            (nest indentSize $ vcat $ punctuate semi $ map makeDoc brs)
            $+$ text "}"
    OnionSub e s -> makeDoc e <+> text "&-" <+> makeDoc s
    OnionProj e s -> makeDoc e <+> text "&." <+> makeDoc s
    EmptyOnion -> text "(&)"
    LazyOp op e1 e2 -> parens $ makeDoc e1 <+> makeDoc op <+> makeDoc e2
    EagerOp op e1 e2 -> parens $ makeDoc e1 <+> makeDoc op <+> makeDoc e2
    Def m i v e ->
      hsep [text "def", dispMod m, makeDoc i,
            text "=", makeDoc v, text "in", makeDoc e]
    Assign i v e -> hsep [makeDoc i, text "=", makeDoc v, text "in", makeDoc e]
    ExprCell c -> text "Cell #" <> int c
    where dispMod m = case m of
            Just Final -> text "final"
            Just Immutable -> text "immut"
            Nothing -> empty

-- TODO: fix parens
instance Display Value where
  makeDoc x =
    case x of
      VLabel n v -> text "`" <> makeDoc n <+> parens (makeDoc v)
      VOnion v1 v2 -> parens (makeDoc v1) <+> text "&" <+> parens (makeDoc v2)
      VFunc i e -> text "fun" <+> text (unIdent i) <+> text "->" <+> makeDoc e
      VPrimInt i -> text $ show i
      VPrimChar c -> char c
      VPrimUnit -> text "()"
      VEmptyOnion -> text "(&)"

instance Display Branch where
  makeDoc (Branch chi e) =
    makeDoc chi <+> text "->" <+> makeDoc e

instance Display (Chi a) where
  makeDoc chi =
    case chi of
      ChiTopVar x -> iDoc x
      ChiTopOnion p s -> makeDoc p <+> text "&" <+> makeDoc s
      ChiTopBind b -> makeDoc b
      ChiOnionMany p s -> makeDoc p <+> text "&" <+> makeDoc s
      ChiOnionOne p -> makeDoc p
      ChiBound i b -> iDoc i <> text ":" <> makeDoc b
      ChiUnbound p -> makeDoc p
      ChiPrim p -> makeDoc p
      ChiLabelShallow lbl x -> text "`" <> makeDoc lbl <+> iDoc x
      ChiLabelDeep lbl b -> text "`" <> makeDoc lbl <+> makeDoc b
      ChiFun -> text "fun"
      ChiInnerStruct s -> parens $ makeDoc s
    where iDoc = text . unIdent

instance Display Assignable where
  makeDoc (AIdent i) = makeDoc i
  makeDoc (ACell v) = makeDoc v

class Evaluated a where
  value :: a -> Value
  value v = fst $ vmPair v
  mapping :: a -> IntMap Value
  mapping v = snd $ vmPair v

  vmPair :: a -> (Value, IntMap Value)
  vmPair v = (value v, mapping v)

instance Evaluated (Value, IntMap Value) where
  vmPair = id

instance Evaluated Value where
  value = id
  mapping = const IntMap.empty
