{-# LANGUAGE GADTs #-}

module Language.TinyBang.Interpreter.Projection
( project
, projectAll
) where

import Control.Applicative ((<$>),(<*>))
import Data.Maybe (listToMaybe)

import Language.TinyBang.Ast
import Language.TinyBang.Interpreter.Basis
              
-- |Performs single evaluation projection on a given variable and projector.
project :: FlowVar -> AnyProjector -> EvalM (Maybe Value)
project x proj = listToMaybe <$> projectAll x proj

-- |Performs evaluation projection on a given variable and projector.  This
--  projection calculation produces a list in *reverse* order; the first element
--  is the highest priority value.
projectAll :: FlowVar -> AnyProjector -> EvalM [Value]
projectAll x proj = do
  v <- flowLookup x
  case v of
    VOnion _ x' x'' -> (++) <$> projectAll x'' proj <*> projectAll x' proj
    VOnionFilter _ x' op proj' ->
      let fcond = case op of
                    OpOnionSub _ -> (== proj')  
                    OpOnionProj _ -> (/= proj')
      in if fcond proj then return [] else projectAll x' proj
    _ -> return $ if inProjector v proj then [v] else []
  where
    inProjector :: Value -> AnyProjector -> Bool
    inProjector v proj' =
      case (v, proj') of
        (VInt _ _, SomeProjector (ProjPrim _ (PrimInt _))) -> True
        (VChar _ _, SomeProjector (ProjPrim _ (PrimChar _))) -> True
        (VLabel _ n _, SomeProjector (ProjLabel _ n')) | n == n' -> True
        (VScape _ _ _, SomeProjector (ProjFun _)) -> True
        _ -> False
