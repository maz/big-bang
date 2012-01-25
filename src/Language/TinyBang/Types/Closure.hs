{-# LANGUAGE TupleSections #-}
module Language.TinyBang.Types.Closure
( calculateClosure
) where

import Language.TinyBang.Types.Types ( (<:)
                                     , (.:)
                                     , Constraints
                                     , Constraint(..)
                                     , TauDown(..)
                                     , TauUp(..)
                                     , TauChi(..)
                                     , ConstraintHistory(..)
                                     , Alpha(..)
                                     , CallSite(..)
                                     , CallSites(..)
                                     , callSites
                                     , PolyFuncData(..)
                                     , Guard(..)
                                     , PrimitiveType(..)
                                     , Sigma(..)
                                     )
import Language.TinyBang.Types.UtilTypes (LabelName)

import Data.Function.Utils (leastFixedPoint)
import Data.Maybe.Utils (justIf)
import Data.Set.Utils (singIf)

import Control.Exception (assert)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Maybe (catMaybes, fromJust, mapMaybe, listToMaybe, isJust)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Monoid (mappend, mempty)
import Control.Monad.Reader (runReader, ask, local, reader, Reader, MonadReader)
import Control.Monad.Writer (tell, WriterT, execWriterT)
import Control.Monad (guard, join, mzero)
import Control.Applicative ((<$>), (<*>), pure)
import Control.Arrow (second)

type CReader = Reader Constraints

--type CWriter out ret = Writer (Set out) ret

data Compatibility = NotCompatible | MaybeCompatible | CompatibleAs TauDown

histFIXME :: ConstraintHistory
histFIXME = undefined

-- |A function modeling immediate compatibility.  This function takes a type and
--  a guard in a match case.  If the input type is compatible with the guard,
--  this function returns @CompatibleAs t@, where t is the type as which the
--  original type is compatible; otherwise, @NotCompatible@ is
--  returned. MaybeCompatible is returned if the result is not yet determinable,
--  as in the case of lazy operations not yet being closed over.  This function
--  is equivalent to the _ <:: _ ~ _ relation in the documentation.

-- Note that lazy ops match against ChiAny; TODO: is this desired behavior?
immediatelyCompatible :: TauDown
                      -> TauChi
                      -> CReader Compatibility
immediatelyCompatible tau chi =
  case (tau,chi) of
    (_,ChiAny) -> return $ CompatibleAs tau
    (TdPrim p, ChiPrim p') | p == p' -> return $ CompatibleAs tau
    (TdLabel n _, ChiLabel n' _) | n == n' -> return $ CompatibleAs tau
    (TdOnionSub a s, chi) | not $ tSubMatch s chi -> do
      ts <- concretizeType a
      firstCompatibilityInList $ Set.toList ts
    (TdOnion a1 a2, _) -> do
      t1s <- concretizeType a1
      t2s <- concretizeType a2
      firstCompatibilityInList $ Set.toList t1s ++ Set.toList t2s
    (TdFunc _, ChiFun) -> return $ CompatibleAs tau
    (TdLazyOp _ _ _, _) -> return $ MaybeCompatible
    _ -> return $ NotCompatible
    where notCompatible x =
            case x of
              NotCompatible -> True
              _ -> False
          firstCompatibilityInList xs = do
            compatibilities <- sequence [immediatelyCompatible x chi | x <- xs]
            -- If the list is all NotCompatible, it's not compatible; otherwise,
            -- whatever was at the first other answer goes.
            return $
              maybe NotCompatible id $
              listToMaybe $ dropWhile notCompatible compatibilities


tSubMatch sigma chi =
  case (chi, sigma) of
    (ChiPrim p, SubPrim p') -> p == p'
    (ChiLabel n _, SubLabel n') -> n == n'
    (ChiFun, SubFunc) -> True
    _ -> False

-- |A function modeling TCaseBind.  This function creates an appropriate set of
--  constraints to add when a given case branch is taken.  Its primary purpose
--  is to bind a label variable (such as `A x) to the contents of the input.
tCaseBind :: ConstraintHistory
          -> TauDown
          -> TauChi
          -> Constraints
tCaseBind history tau chi =
    case (tau,chi) of
        (TdLabel n tau', ChiLabel n' a) ->
            (tau' <: a .: history)
                `singIf` (n == n')
        _ -> Set.empty

--TODO: Consider adding chains to history and handling them here
--TODO: Docstring this function

concretizeType :: Alpha -> CReader (Set TauDown)
concretizeType a = do
  clbs <- concreteLowerBounds
  ilbs <- intermediateLowerBounds
  rec <- Set.unions <$> mapM concretizeType ilbs
  return $ Set.union (Set.fromList clbs) rec
  where concreteLowerBounds :: CReader [TauDown]
        concreteLowerBounds = do
          constraints <- ask
          return $ do
            LowerSubtype td a' _ <- Set.toAscList constraints
            guard $ a == a'
            return td
        intermediateLowerBounds :: CReader [Alpha]
        intermediateLowerBounds = do
          constraints <- ask
          return $ do
            AlphaSubtype ret a' _ <- Set.toAscList constraints
            guard $ a == a'
            return ret

-- |This function transforms a specified alpha into a call site list.  The
--  resulting call site list is in the reverse order form dictated by the
--  CallSites structure; that is, the list [{'3},{'2},{'1}] represents the type
--  variable with the exponent expression '1^('2^'3).  The resulting call site
--  list is suitable for use in type variable substitution for polymorphic
--  functions.
makeCallSites :: Alpha -> CallSites
makeCallSites alpha@(Alpha alphaId siteList) =
    callSites $
    case rest of
      [] -> -- In this case, this call site is new to the list
        (CallSite $ Set.singleton alphaEntry) : map CallSite siteList'
      (_,cyc):tl -> -- In this case, we found a cycle
        (CallSite cyc):(map (CallSite . fst) tl)
    where unCallSite (CallSite a) = a
          siteList' = map unCallSite $ unCallSites siteList
          alphaEntry = Alpha alphaId $ callSites []
          -- A list of pairs, the snd of which is the union of all the fsts so
          -- far.
          totals :: [(Set Alpha, Set Alpha)]
          totals = zip siteList' $ tail $ scanl Set.union Set.empty siteList'
          rest = dropWhile (not . Set.member alphaEntry . snd) totals

-- |A function which performs substitution on a set of constraints.  All
--  variables in the alpha set are replaced with corresponding versions that
--  have the specified alpha in their call sites list.
substituteVars :: Constraints -> Set Alpha -> Alpha -> Constraints
substituteVars constraints forallVars replAlpha =
  runReader
    (substituteAlpha constraints)
    (replAlpha, forallVars)

closeCases :: Constraints -> Constraints
closeCases cs = Set.unions $ do
  -- Using the list monad
  -- failure to match similar to "continue" statment
  Case alpha guards hist <- Set.toList cs
  tau <- f alpha
  -- Handle contradictions elsewhere, both to improve readability and to be more
  -- like the document.
  Just ret <- return $ join $ listToMaybe $ do
    Guard tauChi cs' <- guards
    case runReader (immediatelyCompatible tau tauChi) cs of
      NotCompatible -> return $ Nothing
      MaybeCompatible -> mzero
      CompatibleAs tau' ->
        return $ Just $ Set.union cs' $ tCaseBind histFIXME tau' tauChi
  return ret
  where f a = Set.toList $ runReader (concretizeType a) cs

findCaseContradictions :: Constraints -> Constraints
findCaseContradictions cs = Set.fromList $ do
  Case alpha guards _ <- Set.toList cs
  tau <- f alpha
  isCont <- return $ null $ do
    Guard tauChi cs' <- guards
    case runReader (immediatelyCompatible tau tauChi) cs of
      NotCompatible -> mzero
      MaybeCompatible -> return ()
      CompatibleAs tau' -> return ()
  guard isCont
  return $ Bottom histFIXME
  where f a = Set.toList $ runReader (concretizeType a) cs

closeApplications :: Constraints -> Constraints
closeApplications cs = Set.unions $ do
  UpperSubtype a (TuFunc ai' ao') _ <- Set.toList cs
  TdFunc (PolyFuncData foralls ai ao cs') <- f a
  t2 <- f ai'
  let cs'' = Set.union cs' $
               Set.fromList [ t2 <: ai .: histFIXME
                            , ao <: ao' .: histFIXME]
  return $ substituteVars cs'' foralls ai'
  where f a = Set.toList $ runReader (concretizeType a) cs

findNonFunctionApplications :: Constraints -> Constraints
findNonFunctionApplications cs = Set.fromList $ do
  UpperSubtype a (TuFunc ai' ao') _ <- Set.toList cs
  tau <- f a
  case tau of
    TdFunc (PolyFuncData foralls ai ao cs') -> mzero
    _ -> return $ Bottom histFIXME
  where f a = Set.toList $ runReader (concretizeType a) cs

closeLops :: Constraints -> Constraints
closeLops cs = Set.fromList $ do
  LowerSubtype (TdLazyOp op a1 a2) a _ <- Set.toList cs
  TdPrim PrimInt <- f a1
  TdPrim PrimInt <- f a2
  return $ TdPrim PrimInt <: a .: histFIXME
  where f a = Set.toList $ runReader (concretizeType a) cs

findLopContradictions :: Constraints -> Constraints
findLopContradictions cs = Set.fromList $ do
  LowerSubtype (TdLazyOp op a1 a2) a _ <- Set.toList cs
  -- Not quite like the document.
  -- FIXME: when we have lops that aren't int -> int -> int, this needs to be
  -- changed.
  tau <- f a1 ++ f a2
  case tau of
    TdPrim PrimInt -> mzero
    _ -> return $ Bottom histFIXME
  where f a = Set.toList $ runReader (concretizeType a) cs

-- The notation ▽τ ▹: △τ is used as a shorthand for ▽τ 􏳒: α ∧ α <: △τ.
propogateCellsForward :: Constraints -> Constraints
propogateCellsForward cs = Set.fromList $ do
  UpperSubtype a (TuCellGet a1) _ <- Set.toList cs
  TdCell a2 <- f a
  t2 <- f a2
  return $ t2 <: a1 .: histFIXME
  where f a = Set.toList $ runReader (concretizeType a) cs

propogateCellsBackward :: Constraints -> Constraints
propogateCellsBackward cs = Set.fromList $ do
  UpperSubtype a (TuCellSet a1) _ <- Set.toList cs
  TdCell a2 <- f a
  t2 <- f a1
  return $ t2 <: a2 .: histFIXME
  where f a = Set.toList $ runReader (concretizeType a) cs

-- |This closure calculation function produces appropriate bottom values for
--  immediate contradictions (such as tprim <: tprim' where tprim != tprim').
closeSingleContradictions :: Constraints -> Constraints
closeSingleContradictions cs =
  Set.unions $ map ($ cs)
    [ id
    , findCaseContradictions
    , findNonFunctionApplications
    , findLopContradictions
    , propogateCellsForward
    , propogateCellsBackward
    ]

closeAll :: Constraints -> Constraints
closeAll cs =
  Set.unions $ map ($ cs)
    [ id
    , closeCases
    , closeApplications
    , closeLops
    ]

-- |Calculates the transitive closure of a set of type constraints.
calculateClosure :: Constraints -> Constraints
calculateClosure c = closeSingleContradictions $ leastFixedPoint closeAll c

type AlphaSubstitutionEnv = (Alpha, Set Alpha)

saHelper constr a = constr <$> substituteAlpha a
saHelper2 constr a1 a2 = constr <$> substituteAlpha a1 <*> substituteAlpha a2

-- |A typeclass for entities which can substitute their type variables.
class AlphaSubstitutable a where
  -- |The alpha in the reader environment is added to superscripts.
  --  The set in the reader environment contains alphas to ignore.
  substituteAlpha :: a -> Reader AlphaSubstitutionEnv a

instance AlphaSubstitutable Alpha where
  substituteAlpha alpha@(Alpha alphaId callSites) = do
    (newAlpha, forallVars) <- ask
    let newCallSites = makeCallSites newAlpha
    if not $ Set.member alpha forallVars
      then return alpha
      -- The variable we are substituting should never have marked
      -- call sites.  The only places where polymorphic function
      -- constraints (forall constraints) are built are by the
      -- inference rules themselves (which have no notion of call
      -- sites) and the type replacement function (which does not
      -- replace forall-ed elements within a forall constraint).
      else assert ((length . unCallSites) callSites == 0) $
         return $ Alpha alphaId newCallSites

instance AlphaSubstitutable TauUp where
  substituteAlpha tu = case tu of
    TuFunc a1 a2 -> saHelper2 TuFunc a1 a2
    TuCellGet a -> saHelper TuCellGet a
    TuCellSet a -> saHelper TuCellSet a

instance AlphaSubstitutable TauDown where
  substituteAlpha td = case td of
    TdLabel n a -> saHelper (TdLabel n) a
    TdOnion a1 a2 -> saHelper2 TdOnion a1 a2
    TdLazyOp op a1 a2 -> saHelper2 (TdLazyOp op) a1 a2
    TdFunc pfd -> saHelper TdFunc pfd
    TdOnionSub a s -> saHelper (`TdOnionSub` s) a
    TdCell a -> saHelper TdCell a
    _ -> return td

instance AlphaSubstitutable PolyFuncData where
  substituteAlpha (PolyFuncData alphas alphaIn alphaOut constraints) =
      PolyFuncData alphas
        <$> substituteAlpha' alphaIn
        <*> substituteAlpha' alphaOut
        <*> substituteAlpha' constraints
      -- The variables described by the forall list should never be replaced
      where substituteAlpha' :: (AlphaSubstitutable a)
                             => a -> Reader AlphaSubstitutionEnv a
            substituteAlpha' =
              local (second $ flip Set.difference alphas) . substituteAlpha

instance AlphaSubstitutable Constraint where
  substituteAlpha c = case c of
      LowerSubtype td a hist -> do
        a' <- substituteAlpha a
        return $ LowerSubtype td a' hist
      UpperSubtype a tu hist -> do
        a' <- substituteAlpha a
        return $ UpperSubtype a' tu hist
      AlphaSubtype a1 a2 hist ->
        AlphaSubtype
          <$> substituteAlpha a1
          <*> substituteAlpha a2
          <*> pure hist
      Case a guards hist ->
        Case
          <$> substituteAlpha a
          <*> mapM substituteAlpha guards
          <*> return hist
      Bottom hist -> return $ Bottom hist

instance AlphaSubstitutable Guard where
  substituteAlpha (Guard tauChi constraints) =
      Guard
        <$> substituteAlpha tauChi
        <*> substituteAlpha constraints

instance AlphaSubstitutable TauChi where
  substituteAlpha c = case c of
      ChiPrim p -> return $ ChiPrim p
      ChiLabel n a -> ChiLabel n <$> substituteAlpha a
      ChiFun -> return ChiFun
      ChiAny -> return ChiAny

instance (Ord a, AlphaSubstitutable a) => AlphaSubstitutable (Set a) where
  substituteAlpha = fmap Set.fromList . mapM substituteAlpha . Set.toList