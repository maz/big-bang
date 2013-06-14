{-# LANGUAGE ScopedTypeVariables, TemplateHaskell, GADTs #-}

{-|
  This module defines TinyBang's projection relation.
-}
module Language.TinyBang.TypeSystem.Relations.Projection
( ProjectionError(..)
, ProjM
, project
, projectSingle
, projectSingleResult
) where

import Control.Applicative
import Control.Arrow ((***))
import Control.Monad.Reader
import Control.Monad.Trans.Either
import Data.Set (Set)
import qualified Data.Set as Set

import Language.TinyBang.Ast
import Language.TinyBang.Display
import Language.TinyBang.Logging
import Language.TinyBang.TypeSystem.Constraints
import Language.TinyBang.TypeSystem.ConstraintDatabase
import Language.TinyBang.TypeSystem.ConstraintHistory
import Language.TinyBang.TypeSystem.Fibrations
import Language.TinyBang.TypeSystem.Monad.Trans.CReader
import Language.TinyBang.TypeSystem.Monad.Trans.Flow
import Language.TinyBang.TypeSystem.Types

$(loggingFunctions)

-- |A data type describing errors projection.
data ProjectionError db
  = NonContractiveType AnyProjector (Type db) [FlowTVar]
  deriving (Eq, Ord, Show)
instance (ConstraintDatabase db, Display db)
      => Display (ProjectionError db) where
  makeDoc (NonContractiveType proj typ vars) =
    text "NonContractiveType" <+> makeDoc proj <+> makeDoc typ <+> makeDoc vars

-- |An alias for the projection monad.
type ProjM db m = FlowT (EitherT (ProjectionError db) m)

-- |Computes the possible projections of a type variable and projector.  This
--  operation occurs in the context of a constraint database.  This
--  implementation differs from the specification in that non-contractive types
--  are prohibited.
--
--  The resulting list of types is in reverse order; the first element of the
--  list is highest priority.
project :: forall db m.
           (Applicative m, ConstraintDatabase db, MonadCReader db m, Display db)
        => AnyProjector
        -> FlowTVar
        -> ProjM db m ([Type db], Fibration db)
project = projectVar (Set.empty,[])

type OccursCheck = (Set FlowTVar, [FlowTVar])

-- TODO: rewrite projectSingle for efficiency.  It should use a different
-- exploration tactic for onions so as to avoid exploring the left side of a
-- tree if it doesn't need it.

-- |Computes the possible single projections of a type variable and projector.
--  See @project@ for more information.
projectSingle :: forall db m.
                 ( Applicative m, ConstraintDatabase db, MonadCReader db m
                 , Display db)
              => AnyProjector
              -> FlowTVar
              -> ProjM db m (Maybe (Type db), Fibration db)
projectSingle proj a = do  
  (typs,fib) <- project proj a
  case typs of
    [] -> return (Nothing, fib)
    typ:_ -> return (Just typ, fib)

-- |Performs single projection.  This obtains a prepared projection result
--  as well as the actual type.
projectSingleResult :: ( ConstraintDatabase db, MonadCReader db m
                       , Functor m, Applicative m, Display db )
                    => AnyProjector -> FlowTVar
                    -> ProjM db m (Maybe (Type db), SingleProjectionResult db)
projectSingleResult proj a = do
  (r,f) <- projectSingle proj a
  return (r, SingleProjectionResult proj a r f)

-- |The *real* projection function.  This function includes an occurs check for
--  non-contractive onion types to prevent divergence.
projectVar :: forall db m.
              ( Applicative m, ConstraintDatabase db, MonadCReader db m
              , Display db)
           => OccursCheck
           -> AnyProjector
           -> FlowTVar
           -> ProjM db m ([Type db], Fibration db)
projectVar check proj a = do
  _debug $ "Checking projection of " ++ display proj ++ " from variable "
              ++ display a
  TypeConstraint lowerBound _ <-
      flow $ lift $ getTypeConstraintsByUpperBound a <$> askDb
  (ts, fib) <- projectType lowerBound
  _debug $ "Projection of " ++ display proj ++ " from variable "
              ++ display a ++ " gives " ++ display ts ++ " at fibration "
              ++ display fib
  return (ts, fib)
  where
    projectType :: Type db -> ProjM db m ([Type db], Fibration db)
    projectType lowerBound =
      case (lowerBound, proj) of
        (Primitive p, SomeProjector (ProjPrim _ p')) | p == p' ->
          return ([lowerBound], Fibration lowerBound [])
        (Label n _, SomeProjector (ProjLabel _ n')) | n == n' ->
          return ([lowerBound], Fibration lowerBound [Unexpanded])
        (Scape _ _ _, SomeProjector (ProjFun _)) ->
          return ([lowerBound], Fibration lowerBound [])
        (Onion a1 a2, _) -> do
          (p1, fib1) <- projectRemembering a1
          (p2, fib2) <- projectRemembering a2
          -- Reverse order: first element is highest priority
          return (p2 ++ p1, Fibration lowerBound [fib1, fib2])
        (OnionFilter a1 (OpOnionSub _) proj', _) | proj /= proj' ->
          projectRemembering a1
        (OnionFilter a1 (OpOnionProj _) proj', _) | proj == proj' ->
          projectRemembering a1
        _ -> return ([], blankFibrationFor lowerBound)
      where
        projectRemembering :: FlowTVar
                           -> ProjM db m ([Type db], Fibration db)
        projectRemembering a' =
          let (aset,alist) = check in
          if Set.member a' aset
            then lift $ left $
                    NonContractiveType proj lowerBound $ reverse alist
            else projectVar ((Set.insert a' *** (a':)) check) proj a'
