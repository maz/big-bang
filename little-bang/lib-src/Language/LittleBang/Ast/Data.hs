module Language.LittleBang.Ast.Data
( Expr(..)
, Var (..)
, Label (..)
, OnionOperator(..)
, BinaryOperator(..)
, OuterPattern(..)
, Pattern(..)
, Projector(..)
, Primitive(..)
) where

-- Haskell module generated by the BNF converter

import Language.TinyBang.Display
import Language.TinyBang.Ast.Data (Origin, HasOrigin, originOf)

-- | AST structure for LittleBang

data Expr =
   ExprDef Origin Var Expr Expr
 | ExprVarIn Origin Var Expr Expr
 | ExprScape Origin OuterPattern Expr
 | ExprBinaryOp Origin Expr BinaryOperator Expr
 | ExprOnionOp Origin Expr OnionOperator Projector
 | ExprOnion Origin Expr Expr
 | ExprAppl Origin Expr Expr
 | ExprLabelExp Origin Label Expr
 | ExprVar Origin Var
 | ExprValInt Origin Integer
 | ExprValChar Origin Char
 | ExprValUnit Origin
  -- For Little Bang
 | ExprCondition Origin Expr Expr Expr
  deriving (Eq,Ord,Show)

data OnionOperator =
   OpOnionSub Origin 
 | OpOnionProj Origin 
  deriving (Eq,Ord,Show)

data BinaryOperator =
   OpPlus Origin
 | OpMinus Origin
 | OpEqual Origin 
 | OpGreater Origin 
 | OpGreaterEq Origin
 | OpLesser Origin 
 | OpLesserEq Origin
  deriving (Eq,Ord,Show)

data OuterPattern =
   OuterPatternLabel Origin Var Pattern
  deriving (Eq,Ord,Show)

data Pattern =
   PrimitivePattern Origin Primitive
 | LabelPattern Origin Label Var Pattern
 | ConjunctionPattern Origin Pattern Pattern 
 | ScapePattern Origin
 | EmptyOnionPattern Origin
  deriving (Eq,Ord,Show)

data Var =
   Var Origin String
  deriving (Eq,Ord,Show)

data Label =
   LabelDef Origin String
  deriving (Eq,Ord,Show)

data Projector =
   PrimitiveProjector Origin Primitive
 | LabelProjector Origin Label
 | FunProjector Origin 
  deriving (Eq,Ord,Show)

data Primitive =
   TInt Origin 
 | TChar Origin 
  deriving (Eq,Ord,Show)

-- | HasOrigin instances for Expr 

instance HasOrigin Expr where
  originOf x = case x of
    ExprDef orig _ _ _ -> orig
    ExprVarIn orig _ _ _ -> orig
    ExprScape orig _ _ -> orig
    ExprBinaryOp orig _ _ _ -> orig
    ExprOnionOp orig _ _ _ -> orig
    ExprOnion orig _ _ -> orig
    ExprAppl orig _ _ -> orig
    ExprLabelExp orig _ _-> orig
    ExprVar orig _ -> orig
    ExprValInt orig _ -> orig
    ExprValChar orig _ -> orig
    ExprValUnit orig -> orig
    -- For Little Bang
    ExprCondition orig _ _ _ -> orig

instance HasOrigin Var where
  originOf x = case x of
    Var orig _ -> orig

instance HasOrigin OuterPattern where
  originOf x = case x of
   OuterPatternLabel orig _ _ -> orig

instance HasOrigin Pattern where
  originOf x = case x of
   ConjunctionPattern orig _ _ -> orig
   LabelPattern orig _ _ _ -> orig
   PrimitivePattern orig _ -> orig
   ScapePattern orig -> orig
   EmptyOnionPattern orig -> orig

instance HasOrigin Primitive where
  originOf x = case x of
   TInt orig -> orig 
   TChar orig -> orig

instance HasOrigin Projector where
  originOf x = case x of
   PrimitiveProjector orig _ -> orig
   LabelProjector orig _ -> orig
   FunProjector orig -> orig

instance HasOrigin Label where
  originOf x = case x of
    LabelDef orig _ -> orig


-- | Display instances for Expr 

instance Display Expr where
  makeDoc x = case x of
   ExprDef _ v e1 e2 -> text "def " <> makeDoc v <> text " = (" <> makeDoc e1 <> text ") in (" <> makeDoc e2 <> text ")"
   ExprVarIn _ v e1 e2 -> makeDoc v <> text " = (" <> makeDoc e1 <> text ") in (" <> makeDoc e2 <> text ")"
   ExprScape _ op e -> text "(" <> makeDoc op <> text ") -> (" <> makeDoc e <> text ")"
   ExprBinaryOp _ e1 ao e2 -> text "(" <> makeDoc e1 <> text ") " <> makeDoc ao <> text " (" <> makeDoc e2 <> text ")"
   ExprOnionOp _ e oo p -> text "(" <> makeDoc e <+> makeDoc oo <+> makeDoc p <> text ")"
   ExprOnion _ e1 e2 -> text "(" <> makeDoc e1 <> text ") & (" <> makeDoc e2 <> text ")"
   ExprAppl _ e1 e2 -> text "(" <> makeDoc e1 <> text ") apply (" <> makeDoc e2 <> text ")"
   ExprLabelExp _ l e -> text "(" <> makeDoc l <+> makeDoc e <> text ")"
   ExprVar _ v -> makeDoc v 
   ExprValInt _ i -> text $ show i
   ExprValChar _ c -> text $ show c
   ExprValUnit _ -> text "()"
   -- For Little Bang
   ExprCondition _ e1 e2 e3 -> text "if " <> makeDoc e1 <> text " then " <> makeDoc e2 <> text " else " <> makeDoc e3

instance Display OnionOperator where
 makeDoc x = case x of
   OpOnionSub _ -> text "&-"
   OpOnionProj _ -> text "&."

instance Display BinaryOperator where
  makeDoc x = case x of
   OpPlus _ -> text "+"
   OpMinus _ -> text "-"
   OpEqual _ -> text "=="
   OpGreater _ -> text ">"
   OpLesser _ -> text "<"
   OpGreaterEq _ -> text ">="
   OpLesserEq _ -> text "<="

instance Display OuterPattern where
  makeDoc x = case x of
   OuterPatternLabel _ var pat -> makeDoc var <> text ":" <> makeDoc pat

instance Display Pattern where
  makeDoc x = case x of
   ConjunctionPattern _ p1 p2 ->  text "(" <> makeDoc p1  <+> text "&pat" <+> makeDoc p2 <> text ")"
   LabelPattern _ l v p -> text "(" <> makeDoc l <+> makeDoc v <> text ":" <> makeDoc p <> text ")" 
   PrimitivePattern _ prim -> makeDoc prim
   ScapePattern _ -> text "fun"
   EmptyOnionPattern _ -> text "()"

instance Display Var where
  makeDoc x = case x of
    Var _ i -> text i

instance Display Label where
  makeDoc x = case x of
    LabelDef _ l -> text $ "`" ++ l

instance Display Primitive where
  makeDoc p = case p of
    TInt _ -> text "int"
    TChar _ -> text "char"

instance Display Projector where
  makeDoc x = case x of
   PrimitiveProjector _ p -> makeDoc p
   LabelProjector _ l -> makeDoc l
   FunProjector _ -> text "fun" 
