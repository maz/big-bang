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
                      -> Compatibility
immediatelyCompatible tau chi =
  case (tau,chi) of
    (_,ChiAny) -> CompatibleAs tau
    (TdPrim p, ChiPrim p') | p == p' -> CompatibleAs tau
    (TdLabel n t, ChiLabel n' a) | n == n' -> CompatibleAs tau
    (TdOnion t1 t2, _) ->
      case (immediatelyCompatible t1 chi, immediatelyCompatible t2 chi) of
        (_, MaybeCompatible) -> MaybeCompatible
        (c, NotCompatible) -> c
        -- If we reach this case, we must have found compatibility in the second
        -- onion.
        (_, c) -> c
    (TdFunc _, ChiFun) -> CompatibleAs tau
    (TdLazyOp _ _ _, _) -> MaybeCompatible
    -- The line below is not strictly necessary, but included for clarity.
    (TdAlpha a, _) -> NotCompatible
    _ -> NotCompatible

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
            (tau' <: TuAlpha a .: history)
                `singIf` (n == n')
        _ -> Set.empty

getLowerBound :: Constraint -> Maybe TauDown
getLowerBound c =
  case c of
    Subtype td _ _ -> Just td
    _ -> Nothing

getUpperBound :: Constraint -> Maybe TauUp
getUpperBound c =
  case c of
    Subtype _ tu _ -> Just tu
    _ -> Nothing

getHistory :: Constraint -> ConstraintHistory
getHistory c =
  case c of
    Subtype _ _ h -> h
    Case _ _ h -> h
    Bottom h -> h

filterByUpperBound :: Constraints -> TauUp -> Constraints
filterByUpperBound cs t = Set.filter f cs
  where f c = Just t == getUpperBound c

filterByLowerBound :: Constraints -> TauDown -> Constraints
filterByLowerBound cs t = Set.filter f cs
  where f c = Just t == getLowerBound c

--getByUpperBound :: Constraints -> T.TauUp -> Set (T.TauDown, T.ConstraintHistory)
--getByUpperBound cs t = Set.fromAscList $ mapMaybe

--TODO: Consider adding chains to history and handling them here

findConcreteLowerBounds :: TauUp -> CReader (Set TauDown)
findConcreteLowerBounds t = execWriterT $ do
  ilbs <- immediateLowerBounds t
  mapM_ accumulateLBs ilbs
  where -- The folowing type signature is morally but not technically correct
--      immediateLowerBounds :: TauUp -> CReader [TauDown]
        immediateLowerBounds tu =
          mapMaybe getLowerBound . Set.toList <$> mFilter tu
        accumulateLBs :: TauDown -> WriterT (Set TauDown) CReader ()
        accumulateLBs td =
          case td of
            TdAlpha a -> do
              ilbs <- immediateLowerBounds $ TuAlpha a
              mapM_ accumulateLBs ilbs
            _ -> tell $ Set.singleton td
        mFilter x = filterByUpperBound <$> ask <*> pure x

concretizeType :: TauDown -> CReader (Set TauDown)
concretizeType t =
  case t of
    TdOnion t1 t2 -> do
      c1 <- concretizeType t1
      c2 <- concretizeType t2
      return $ Set.map (uncurry TdOnion) $ crossProduct c1 c2
    TdAlpha a -> Set.unions <$> (mapM concretizeType =<< lowerBounds a)
    _ -> return $ Set.singleton t
    where crossProduct xs ys = Set.fromList
            [(x,y) | x <- Set.toList xs, y <- Set.toList ys]
          lowerBounds :: Alpha -> CReader [TauDown]
          lowerBounds alpha =
            mapMaybe getLowerBound . Set.toList <$>
            reader (`filterByUpperBound` TuAlpha alpha)

-- findAlphaOnRight :: Constraints
--                  -> Map T.Alpha (Set (T.TauDown, Constraint))
-- findAlphaOnRight = Map.unionsWith mappend . map fn . Set.toList
--   where fn c =
--           case c of
--             T.Subtype a (T.TuAlpha b) _ ->
--               Map.singleton b $ Set.singleton (a, c)
--             _ -> Map.empty

-- findAlphaOnLeft :: Constraints
--                 -> Map T.Alpha (Set (T.TauUpClosed, Constraint))
-- findAlphaOnLeft = Map.unionsWith mappend . map fn . Set.toList
--   where fn c =
--           case c of
--             T.Subtype (T.TdAlpha a) b _ -> Map.singleton a $
--                                               Set.singleton (b, c)
--             _                            -> Map.empty

-- findLblAlphaOnLeft :: Constraints
--                    -> Map T.Alpha (Set ( LabelName
--                                        , T.TauUpClosed
--                                        , Constraint))
-- findLblAlphaOnLeft = Map.unionsWith mappend . map fn . Set.toList
--   where fn c =
--           case c of
--             T.Subtype (T.TdLabel lbl (T.TdAlpha a)) b _ ->
--               Map.singleton a $ Set.singleton (lbl, b, c)
--             _ -> Map.empty

-- findPolyFuncs :: Constraints
--               -> Map T.Alpha (Set (T.Alpha, T.PolyFuncData, Constraint))
-- findPolyFuncs = Map.unionsWith mappend . map fn . Set.toList
--   where fn c =
--           case c of
--             T.Subtype (T.TdFunc pfd) (T.TuFunc ai ao) _ ->
--                 Map.singleton ai $ Set.singleton (ao, pfd, c)
--             _ -> Map.empty

-- findAlphaAmpPairs :: Constraints
--                   -> Map (T.Alpha, T.Alpha) (Set ( T.TauUp
--                                                  , Constraint))
-- findAlphaAmpPairs = Map.unionsWith mappend . map fn . Set.toList
--   where fn c =
--           case c of
--             T.Subtype (T.TdOnion (T.TdAlpha a) (T.TdAlpha b)) d _ ->
--               Map.singleton (a,b) $ Set.singleton (d, c)
--             _ -> Map.empty

findCases :: Constraints -> Map Alpha (Set ([Guard], Constraint))
findCases = Map.unionsWith mappend . map fn . Set.toList
  where fn c =
          case c of
            Case a gs _ -> Map.singleton a $ Set.singleton (gs, c)
            _ -> Map.empty

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
  tau <- f $ TdAlpha alpha
  -- Handle contradictions elsewhere, both to improve readability and to be more
  -- like the document.
  Just ret <- return $ join $ listToMaybe $ do
    Guard tauChi cs' <- guards
    case immediatelyCompatible tau tauChi of
      NotCompatible -> return $ Nothing
      MaybeCompatible -> mzero
      CompatibleAs tau' ->
        return $ Just $ Set.union cs' $ tCaseBind undefined tau' tauChi
  return ret
  where f t = Set.toList $ runReader (concretizeType t) cs

findCaseContradictions :: Constraints -> Constraints
findCaseContradictions cs = Set.fromList $ do
  c@(Case alpha guards hist) <- Set.toList cs
  tau <- f $ TdAlpha alpha
  isCont <- return $ null $ do
    Guard tauChi cs' <- guards
    case immediatelyCompatible tau tauChi of
      NotCompatible -> mzero
      MaybeCompatible -> return ()
      CompatibleAs tau' -> return ()
  guard isCont
  return $ Bottom $ ContradictionCase undefined c
  where f t = Set.toList $ runReader (concretizeType t) cs

closeApplications :: Constraints -> Constraints
closeApplications cs = Set.unions $ do
  Subtype t1 (TuFunc ai' ao') hist <- Set.toList cs
  TdFunc (PolyFuncData foralls ai ao cs') <- f t1
  t2 <- f $ TdAlpha ai'
  let cs' = Set.union cs $
              Set.fromList [ t2 <: TuAlpha ai .: undefined
                           , TdAlpha ao <: TuAlpha ao' .: undefined]
  return $ substituteVars cs' foralls ai'
  where f t = Set.toList $ runReader (concretizeType t) cs

findNonFunctionApplications :: Constraints -> Constraints
findNonFunctionApplications cs = Set.fromList $ do
  c@(Subtype t (TuFunc ai' ao') hist) <- Set.toList cs
  tau <- f t
  case tau of
    TdFunc (PolyFuncData foralls ai ao cs') -> mzero
    _ -> return $ Bottom undefined
  where f t = Set.toList $ runReader (concretizeType t) cs

closeLops :: Constraints -> Constraints
closeLops cs = Set.fromList $ do
  Subtype (TdLazyOp t1 op t2) tu hist <- Set.toList cs
  -- Horribly inefficient
  -- TODO: trivial optimization if necessary
  c1 <- f t1
  c2 <- f t2
  case (c1, c2) of
    (TdPrim PrimInt, TdPrim PrimInt) ->
      -- TODO: fix use of undefined to stand in for ConstraintHistory below.
      return $ TdPrim PrimInt <: tu .: undefined
    _ -> mzero
  where f t = Set.toList $ runReader (concretizeType t) cs

findLopContradictions :: Constraints -> Constraints
findLopContradictions cs = Set.fromList $ do
  Subtype (TdLazyOp t1 op t2) tu hist <- Set.toList cs
  -- Not quite like the document.
  -- FIXME: when we have lops that aren't int -> -- int -> int, this needs to be
  -- changed.
  tau <- f t1 ++ f t2
  case tau of
    TdPrim PrimInt -> mzero
    _ -> return $ Bottom undefined
  where f t = Set.toList $ runReader (concretizeType t) cs

-- |This closure calculation function produces appropriate bottom values for
--  immediate contradictions (such as tprim <: tprim' where tprim != tprim').
closeSingleContradictions :: Constraints -> Constraints
closeSingleContradictions cs = error "Not yet implemented"

closeAll :: Constraints -> Constraints
closeAll c = Set.unions $ map ($ c)
        [ id
        , closeCases
        , closeApplications
        , closeLops
        ]

-- |Calculates the transitive closure of a set of type constraints.
calculateClosure :: Constraints -> Constraints
calculateClosure c = leastFixedPoint closeAll c

type AlphaSubstitutionEnv = (Alpha, Set Alpha)

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
  substituteAlpha tau =
    case tau of
      TuFunc ai ao ->
        TuFunc
          <$> substituteAlpha ai
          <*> substituteAlpha ao
      TuAlpha a -> TuAlpha <$> substituteAlpha a

instance AlphaSubstitutable TauDown where
  substituteAlpha tau =
    case tau of
      TdPrim p -> return $ TdPrim p
      TdLabel n t -> TdLabel n <$> substituteAlpha t
      TdOnion t1 t2 ->
        TdOnion
          <$> substituteAlpha t1
          <*> substituteAlpha t2
      TdFunc pfd -> TdFunc <$> substituteAlpha pfd
      TdAlpha a -> TdAlpha <$> substituteAlpha a
      TdLazyOp t1 op t2 ->
        TdLazyOp <$> substituteAlpha t1 <*> pure op <*> substituteAlpha t2

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
      Subtype td tu hist ->
        Subtype
          <$> substituteAlpha td
          <*> substituteAlpha tu
          <*> return hist
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
