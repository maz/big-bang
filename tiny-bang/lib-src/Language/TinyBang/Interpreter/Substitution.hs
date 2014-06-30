{-# LANGUAGE TemplateHaskell, MultiParamTypeClasses, FlexibleContexts, UndecidableInstances #-}

module Language.TinyBang.Interpreter.Substitution
( substitute
) where

import Control.Applicative
import Data.Map (Map)
import qualified Data.Map as Map

import Language.TinyBang.Ast
import Language.TinyBang.Utils.TemplateHaskell.Transform

-- |Performs a syntactic substitution of variables in the provided expression.
--  This substitution is not capture-avoiding; the expression must be
--  well-formed (at most one definition per variable) or this function may not
--  produce desired results.
substitute :: Map Var Var -> Expr -> Expr
substitute m = transform (VariableSubstitution m)

-- |The data type representing variable substitution.
data VariableSubstitution = VariableSubstitution (Map Var Var)

$(concat <$> mapM (defineHomInstance ''VariableSubstitution)
                  [ ''Expr
                  , ''Clause
                  , ''Redex
                  , ''Value
                  , ''Pattern
                  , ''PatternClause
                  , ''PatternValue
                  ])
$(concat <$> mapM (defineTransformIdentityInstance ''VariableSubstitution)
                  [ ''PrimitiveType
                  , ''LabelName
                  , ''PrimitiveValue
                  , ''BuiltinOp
                  ])
$(defineCommonHomInstances ''VariableSubstitution)

instance Transform VariableSubstitution Var where
  transform (VariableSubstitution m) x = Map.findWithDefault x x m
instance Transform VariableSubstitution Origin where
  -- TODO: more informative generated location
  transform _ _ = generated
