{-# LANGUAGE FlexibleInstances,
             FlexibleContexts,
             MultiParamTypeClasses,
             TupleSections,
             ImplicitParams,
             GADTs,
             TypeSynonymInstances,
             ScopedTypeVariables,
             UndecidableInstances
             #-}

{- |A module defining a Big Bang interpreter.
-}
module Language.TinyBang.Interpreter.Interpreter
( evalTop
, eval
, EvalError(..)
, EvalM
, canonicalize
, onion
) where

import Control.Monad.Error (Error, strMsg, throwError)
import Control.Monad.State (StateT, runStateT, get, put, gets, modify)
import Control.Monad.Reader (ReaderT, Reader, asks, ask, runReader)
import Control.Monad.Identity (Identity)
import Control.Arrow (second)
import Control.Applicative ((<$>))
import Data.Function (on)
import Data.List(foldl1', sort, sortBy, groupBy, nubBy)
import qualified Data.IntMap as IntMap
import Data.IntMap (IntMap, (!))
import Control.Monad.Writer (tell, listen, execWriter, Writer)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe (listToMaybe)

import Language.TinyBang.Ast
  ( Pattern(..)
  , PrimaryPattern(..)
  , ExprPart(..)
  , Value(..)
  , LazyOperator(..)
  , EagerOperator(..)
  , ProjTerm(..)
  , CellId
  )
import qualified Language.TinyBang.Interpreter.Ast as IA
import qualified Language.TinyBang.Config as Cfg
import qualified Language.TinyBang.Types.Types as T
import Language.TinyBang.Types.UtilTypes
    ( Ident
    , unIdent
    , LabelName
    , labelName
    )
import Utils.Language.Ast
import Utils.Render.Display

-- TODO: remove
-- import Debug.Trace

-- |This data type is used to indicate the mode of failure in
-- eApplScape.
data ApplScapeError
 = NoScape -- ^ indicates that no scapes were returned in the
           -- projection.
 | NoMatch -- ^ indicates that scapes were found, but none could take
           -- the provided value as input.
  deriving (Eq, Ord, Enum)

-- |An error type for evaluation failures.
data EvalError t =
      ApplNotScape (Value t) (Value t)
    | DynamicTypeError String -- TODO: figure out what goes here
    | NotClosed Ident
    | UnmatchedScape (Value t) (Value t)
    | IllegalComparison EagerOperator (Value t) (Value t)
    deriving (Eq, Show)
instance Error (EvalError t) where
  strMsg = error
instance (Display t) => Display (EvalError t) where
  makeDoc ee =
    case ee of
      ApplNotScape e e' ->
        text "Attempted to apply" <+> makeDoc e <+> text "to" <+>
        makeDoc e' <+> text "but the prior contains no scapes"
      DynamicTypeError str ->
        -- TODO: not a string!
        text "Dynamic type error:" <+> text str
      NotClosed i ->
        text "Expression not closed for variable" <+> (text $ unIdent i)
      UnmatchedScape e scape ->
        text "The value" <+> makeDoc e <+>
        text "cannot be matched by value" $$
        (nest 4 $ makeDoc scape)
      IllegalComparison op v1 v2 ->
        text "The comparison" <+> makeDoc op <+> makeDoc v1 <+> makeDoc v2 <+>
        text "cannot be is not well typed."

-- I'm not sure if this or the other order of the monad transformers is
-- preferable to the alternative. TODO: figure it out.
type EvalM t a = StateT (CellMap t) (Either (EvalError t)) a
type EnvReader t a = Reader (CellMap t) a
type Cell = Int
type NextCell = Int
type CellMap t = (NextCell, IntMap (Value t))
type Result t = (Value t, IntMap (Value t))

class CellReadable t m where
  readCell :: Cell -> m (Value t)

instance CellReadable t (StateT (CellMap t) (Either (EvalError t))) where
  readCell i = gets snd >>= return . (! i)

instance CellReadable t (ReaderT (CellMap t) Identity) where
  readCell i = asks snd >>= return . (! i)

runEvalMReader :: EnvReader t a -> EvalM t a
runEvalMReader envReader = get >>= return . runReader envReader

newCell :: Value t -> EvalM t Cell
newCell v = do
  (i, m) <- get
  put (i + 1, IntMap.insert i v m)
  return i

--readCell :: Cell -> EvalM Value
--readCell i = gets snd >>= return . (! i)

writeCell :: Cell -> Value t -> EvalM t ()
writeCell i v = modify (second $ IntMap.adjust (const v) i)

------------------------------------------------------------------------------
-- *Evaluation Functions
-- $EvaluationFunctions
--
-- Definitions for functions related to expression evaluation.

-- |Performs an evaluation of a TinyBang expression.
evalTop :: forall ast xast.
           (?conf :: Cfg.Config
          , AstOp HomOp ast ((ast -> xast) -> xast)
          , AstOp EvalOp xast (Cfg.Config -> EvalM xast (Value xast))
           )
        => ast -> Either (EvalError xast) (Result xast)
evalTop e =
    let e' = (upcast e :: xast) in
    fmap (second snd) $ runStateT (eval e') (0, IntMap.empty)

onion :: Value t -> Value t -> Value t
onion VEmptyOnion v = v
onion v VEmptyOnion = v
onion v1 v2 = VOnion v1 v2

type IdMap = Map Ident CellId

-- |Evaluates a TinyBang expression.
eval :: (?conf :: Cfg.Config
        , AstOp EvalOp ast (Cfg.Config -> EvalM ast (Value ast)))
     => ast -> EvalM ast (Value ast)
eval e = astop EvalOp e ?conf
data EvalOp = EvalOp

-- Provides evaluation behavior for intermediate nodes.
instance (AstOp EvalOp ast (Cfg.Config -> EvalM ast (Value ast))
        , AstWrap IA.ExprPart ast)
      => AstStep EvalOp IA.ExprPart ast (Cfg.Config -> EvalM ast (Value ast))
    where
  aststep EvalOp ast = \config -> let ?conf = config in
    case ast of
      IA.ExprCell c -> readCell c
      IA.AssignCell c e1 e2 -> do
        v1 <- eval e1
        writeCell c v1
        eval e2

-- Provides evaluation behavior for TinyBang nodes.
instance (Eq ast, Display ast
        , AstOp EvalOp ast (Cfg.Config -> EvalM ast (Value ast))
        , AstOp IA.SubstCellOp ast (CellId -> Ident -> ast)
        , AstWrap ExprPart ast
        , AstWrap IA.ExprPart ast)
      => AstStep EvalOp ExprPart ast (Cfg.Config -> EvalM ast (Value ast)) where
  aststep EvalOp ast = \config -> let ?conf = config in
    case ast of
      Scape pat e -> return $ VScape pat e
--      Func i e -> return $ VFunc i e
      PrimInt i -> return $ VPrimInt i
      PrimChar c -> return $ VPrimChar c
      PrimUnit -> return $ VPrimUnit
      Var i -> throwError $ NotClosed i
      Label n _ e -> do
        v <- eval e
        c <- newCell v
        return $ VLabel n c
      Onion e1 e2 -> do
        v1 <- eval e1
        v2 <- eval e2
        return $ onion v1 v2
      OnionSub e s -> do
        v <- eval e
        return $ onionSub v
        where onionSub v =
                case (v, s) of
                  (VOnion v1 v2, _) -> onion (onionSub v1) (onionSub v2)
                  (VPrimInt _, ProjPrim T.PrimInt) -> VEmptyOnion
                  (VPrimChar _, ProjPrim T.PrimChar) -> VEmptyOnion
                  (VPrimUnit, ProjPrim T.PrimUnit) -> VEmptyOnion
                  (VScape _ _, ProjFunc) -> VEmptyOnion
--                  (VFunc _ _, ProjFunc) -> VEmptyOnion
                  (VLabel n _, ProjLabel n') | n == n' -> VEmptyOnion
                  _ -> v
      OnionProj e' s -> do
        v <- eval e'
        return $ onionProj v
        where onionProj v =
                case (v, s) of
                  (VOnion v1 v2, _) -> onion (onionProj v1) (onionProj v2)
                  (VPrimInt _, ProjPrim T.PrimInt) -> v
                  (VPrimChar _, ProjPrim T.PrimChar) -> v
                  (VPrimUnit, ProjPrim T.PrimUnit) -> v
                  (VScape _ _, ProjFunc) -> v
--                  (VFunc _ _, ProjFunc) -> v
                  (VLabel n _, ProjLabel n') | n == n' -> v
                  _ -> VEmptyOnion
      EmptyOnion -> return $ VEmptyOnion
      Appl e1 e2 -> do
        v1 <- eval e1
        v2 <- eval e2
        e4 <- eApplScape (eProj v1 ProjFunc) v2
        either (\left ->
                 case left of
                   NoScape -> throwError $ ApplNotScape v1 v2
                   NoMatch -> throwError $ UnmatchedScape v2 v1) eval e4
--        case v1' of
--          Just (VFunc i body) -> eval $ IA.substCell body cellId i
--          _ -> throwError $ ApplNotFunction v1 v2
--      Case e' branches -> do
--        v <- eval e'
----        let answers = mapMaybe (eMatch v) branches
--        let findAnswer bs =
--              case bs of
--                [] -> throwError $ UnmatchedCase v branches
--                b:bs' -> do
--                  mExpr <- eMatch v b
--                  case mExpr of
--                    Nothing -> findAnswer bs'
--                    Just expr -> return expr
--        eval =<< findAnswer branches
        where eApplScape :: (AstOp IA.SubstCellOp ast (CellId -> Ident -> ast)
                            ,AstWrap ExprPart ast
                            ,AstWrap IA.ExprPart ast)
                         => [Value ast] -> Value ast
                         -> EvalM ast (Either ApplScapeError ast)
              -- scape list must be provided in order of precedence
              eApplScape list input =
                if null matches
                    then return $ Left NoScape
                    else do
                      firstMatch <- firstMatchM
                      case firstMatch of
                        Just v -> return $ Right v
                        Nothing -> return $ Left NoMatch
                where scapeList = map unScape list
                      unScape x =
                        case x of
                          VScape pat e' -> (pat, e')
                          _             ->
                            error "Non-scape value received in eApplScape list"
                      -- The mapping has been separated from the monadic
                      -- evaluation to ensure that no eMatch is called unless
                      -- necessary.
                      matches =
                        map (\(pat, e') -> eMatch pat input e') scapeList
                      findMatch mmexprs = do
                        case mmexprs of
                          [] -> return Nothing
                          x:xs -> do
                            mexpr <- x
                            case mexpr of
                              Just _ -> return mexpr
                              Nothing -> findMatch xs
                      firstMatchM :: EvalM ast (Maybe ast)
                      firstMatchM = findMatch matches
              eMatch :: (AstOp IA.SubstCellOp ast (CellId -> Ident -> ast)
                        ,AstWrap ExprPart ast
                        ,AstWrap IA.ExprPart ast)
                     => Pattern -> Value ast -> ast -> EvalM ast (Maybe ast)
              eMatch pat v1 e1' = do -- EvalM
                m <- eSearch pat v1
                return $ do -- Maybe
                  b <- m
                  return $ eSubstAll e1' b
              eSubstAll :: (AstOp IA.SubstCellOp ast (CellId -> Ident -> ast)
                           ,AstWrap ExprPart ast
                           ,AstWrap IA.ExprPart ast)
                        => ast -> IdMap -> ast
              eSubstAll expr b = Map.foldrWithKey foldSubst expr b
                where foldSubst ident cellid sexpr =
                        IA.substCell sexpr cellid ident
              eSearchPri :: PrimaryPattern
                         -> Value ast -> EnvReader ast (Maybe IdMap)
              eSearchPri pat v =
                case pat of
                  PatPrim tprim | not $ null $ eProj v (ProjPrim tprim) ->
                    return $ Just Map.empty
                  PatLabel lbl i pp -> maybe (return Nothing) id $ do
                    -- eProj should never return a list whose first element
                    -- isn't a label when called with the label projector
                    VLabel _ c <- listToMaybe $ eProj v (ProjLabel lbl)
                    return $ do -- EvalM
                      mIdmap <- eSearchPri pp =<< readCell c
                      return $ (`Map.union` Map.singleton i c) <$> mIdmap
                  PatOnion pps -> do -- EnvReader
                    mMaps <- mapM (`eSearchPri` v) pps
                    return $ Map.unions <$> sequence mMaps
                  PatFun | not $ null $ eProj v ProjFunc ->
                    return $ Just Map.empty
                  -- In case of an empty list, fail
                  _ -> return Nothing
              eSearch :: Pattern -> Value ast -> EvalM ast (Maybe IdMap)
              eSearch (Pattern i pp) v = do
                binders <- runEvalMReader $ eSearchPri pp v
                c <- newCell v
                return $ (`Map.union` Map.singleton i c) <$> binders
      Def _ i e1 e2 -> do
        v1 <- eval e1
        cellId <- newCell v1
        eval $ IA.substCell e2 cellId i
      Assign i _ _ -> throwError $ NotClosed i
      LazyOp op e1 e2 -> do
        v1 <- eval e1
        v2 <- eval e2
        let eProjInt = (`eProj` ProjPrim T.PrimInt)
        case (op, eProjInt v1, eProjInt v2) of
          (Plus,  (VPrimInt x:_), (VPrimInt y:_)) ->
            return $ VPrimInt $ x + y
          (Minus, (VPrimInt x:_), (VPrimInt y:_)) ->
            return $ VPrimInt $ x - y
          _ -> throwError $ DynamicTypeError "Uncaught type error in integer operation."
      EagerOp op e1 e2 -> do
        v1 <- eval e1
        v2 <- eval e2
        case op of
          Equal -> eEqual v1 v2
          LessEqual -> eLessEq v1 v2
          GreaterEqual -> eGreaterEq v1 v2
        where eEqual :: (?conf :: Cfg.Config, Display ast)
                     => Value ast -> Value ast -> EvalM ast (Value ast)
              eEqual v1 v2 = do
                c <- newCell VPrimUnit
                b1 <- runEvalMReader $ eCompare v1 v2
                b2 <- runEvalMReader $ eCompare v2 v1
                let n = if b1 && b2 then "True" else "False"
                return $ VLabel (labelName n) c
              eLessEq :: (Eq ast, Display ast)
                      => Value ast -> Value ast -> EvalM ast (Value ast)
              eLessEq v1 v2 = do
                c <- newCell VPrimUnit
                b <- runEvalMReader $ eCompare v1 v2
                let n = if b then "True" else "False"
                return $ VLabel (labelName n) c
              eGreaterEq :: Value ast -> Value ast -> EvalM ast (Value ast)
              eGreaterEq v1 v2 = eLessEq v2 v1
              eCompare :: (?conf :: Cfg.Config, Eq ast, Display ast)
                       => Value ast -> Value ast -> EnvReader ast Bool
              eCompare v1 v2 = do
                env <- ask
                let cmp x y = runReader (eAtomOrder x y) env
                eListLessEq
                  (reverse $ sortBy cmp $ eFilter $ eFlatten v1)
                  (reverse $ sortBy cmp $ eFilter $ eFlatten v2)
              eAtomOrder :: (?conf :: Cfg.Config, Eq ast, Display ast)
                         => Value ast -> Value ast -> EnvReader ast Ordering
              eAtomOrder v1 v2 = do
                b1 <- eAtomCompare v1 v2
                b2 <- eAtomCompare v2 v1
                case (b1,b2) of
                  (True,True) -> return EQ
                  (True,False) -> return LT
                  (False,True) -> return GT
                  (False,False) ->
                    error $ "eAtomCompare returned false for <= and >= "++
                            "of arguments (" ++ display v1 ++ "), " ++
                            "(" ++ display v2 ++ ")"
              eFilter :: [Value ast] -> [Value ast]
              eFilter vs = reverse $ nubBy eTestMatch (reverse vs)
              eTestMatch :: Value ast -> Value ast -> Bool
              eTestMatch v1 v2 =
                case (v1,v2) of
                  (VPrimUnit,VPrimUnit) -> True
                  (VPrimInt _,VPrimInt _) -> True
                  (VPrimChar _,VPrimChar _) -> True
                  (VLabel n _, VLabel n' _) -> n == n'
                  (VScape _ _, VScape _ _) -> True
--                  (VFunc _ _, VFunc _ _) -> True
                  _ -> False
              eListLessEq :: (Eq ast, Display ast)
                          => [Value ast] -> [Value ast] -> EnvReader ast Bool
              eListLessEq vs1 vs2 = do
                case (vs1,vs2) of
                  ([],_) -> return True
                  (_,[]) -> return False
                  (v1:r1,v2:r2) -> do
                    ord <- eAtomOrder v1 v2
                    case ord of
                      LT -> return True
                      GT -> return False
                      EQ -> eListLessEq r1 r2
              eAtomCompare :: (Eq ast, Display ast)
                           => Value ast -> Value ast -> EnvReader ast Bool
              eAtomCompare v1 v2 =
                case (v1,v2) of
                  (VPrimUnit, VPrimUnit) -> return True
                  (VPrimInt p1, VPrimInt p2) -> return $ p1 <= p2
                  (VPrimChar p1, VPrimChar p2) -> return $ p1 <= p2
                  (VLabel n1 c1, VLabel n2 c2) | n1 == n2 -> do
                    v1' <- readCell c1
                    v2' <- readCell c2
                    eCompare v1' v2'
                  (VScape _ _, VScape _ _) -> return $ v1 == v2
--                  (VFunc _ _, VFunc _ _) -> return $ v1 == v2
                  _ | (valueToOrd v1) < (valueToOrd v2) -> return True
                  _ -> return False


-- |Flattens onions to a list whose elements are guaranteed not to
--  be onions themselves and which appear in the same order as they
--  did in the original onion
eFlatten :: Value ast -> [Value ast]
eFlatten e =
  case e of
    VEmptyOnion -> []
    VOnion e1 e2 -> eFlatten e1 ++ eFlatten e2
    _            -> [e]

-- |Transforms a list representing a flattened onion to one containing
--  no type duplicates.
canonicalizeList :: [Value ast] -> [Value ast]
canonicalizeList xs = map last ys
  where ys = groupBy eqValues $ sortBy compareValues xs

-- |Transforms an onion into canonical form.  Canonical form requires
--  that there be no duplicate labels, that the onion be left leaning,
--  and that the onion entries be sorted in accordance with the ordering
--  defined over Values
canonicalizeOnion :: (Ord ast) => Value ast -> Value ast
canonicalizeOnion = foldl1' onion . sort . canonicalizeList . eFlatten

-- Still useful: commented out to silence "Defined but not used" warnings.
-- onionListLessEq _ [] _  = Just True
-- onionListLessEq _ _  [] = Nothing
-- onionListLessEq cmp (x:xs) (y:ys) =
--   case compareValues x y of
--     LT -> onionListLessEq cmp xs (y:ys)
--     EQ -> (&& cmp x y) <$> onionListLessEq cmp xs ys
--     GT -> onionListLessEq cmp (x:xs) ys

data ValueOrdinal
  = OrdPrimUnit
  | OrdPrimInt
  | OrdPrimChar
  | OrdLabel LabelName
  | OrdScape
  deriving (Eq, Ord)

-- Still useful: commented out to silence "Defined but not used" warnings.
-- leqValues = (<=) `on` valueToOrd

compareValues :: Value ast -> Value ast -> Ordering
compareValues = compare `on` valueToOrd

eqValues :: Value ast -> Value ast -> Bool
eqValues = (==) `on` valueToOrd

valueToOrd :: Value ast -> ValueOrdinal
valueToOrd v =
  case v of
    VPrimUnit -> OrdPrimUnit
    VPrimInt _ -> OrdPrimInt
    VPrimChar _ -> OrdPrimChar
    VLabel n _ -> OrdLabel n
    VScape _ _ -> OrdScape
--    VFunc _ _ -> OrdFunc
    _ -> error "This value should not be inside an onion"

-- Still useful: commented out to silence "Defined but not used" warnings.
-- onionEq :: Value -> Value -> Bool
-- onionEq o1 o2 = c o1 == c o2
--   where c = canonicalizeList . eFlatten

-- onionValueEq :: Value -> Value -> Bool
-- onionValueEq o v = c o == [v]
--   where c = canonicalizeList . eFlatten

-- |This function takes a value-mapping pair and returns a new one in
--  canonical form.  Canonical form requires that there be no repeated
--  labels, no unreachable cells, and that the cells' names are
--  determined by position in the value.
canonicalize :: (Ord t) => Result t -> Result t
canonicalize (v, imap) = canonicalize' (v', imap)
  where v' = case v of
               VOnion _ _ -> canonicalizeOnion v
               _ -> v

-- |Helper function for 'canonicalize', which assumes that its input has
--  been deduped if it's an onion.
canonicalize' :: Result t -> Result t
canonicalize' (v, imap) =
  (valueRemap v, imapRemap imap)
  where -- FIXME: Make more efficient later if neccessary
        gatherCells :: Value ast -> Writer [CellId] ()
        gatherCells v' = do
          case v' of
            VLabel _ c -> tell [c]
            VOnion v1 v2 -> gatherCells v1 >> gatherCells v2
            _ -> return ()
        followCellRefs :: Value ast -> Writer [CellId] ()
        followCellRefs v' = do
          cs <- snd <$> listen (gatherCells v')
          mapM_ followCellRefs $ map (imap !) cs
        remap :: IntMap CellId
        remap = IntMap.fromList $ (\x -> zip (map fst x) [0 :: Int ..]) $
                  IntMap.toList $ IntMap.fromListWith (flip const) $
                  zip (execWriter $ followCellRefs v) [0 :: Int ..]
        valueRemap v' =
          case v' of
            VLabel n c -> VLabel n $ remap ! c
            VOnion v1 v2 -> VOnion (valueRemap v1) (valueRemap v2)
            _ -> v'
        imapRemap imap' =
          IntMap.fromList $ map pairRemap $
            filter ((`IntMap.member` remap) . fst) $ IntMap.assocs imap'
        pairRemap (cell, contents) =
          (remap ! cell, valueRemap contents)

-- |Projects values by type. The output list is in precedence order.

-- More generally speaking, the return type of this is a pointed
-- monoid.
eProj :: Value ast -> ProjTerm -> [Value ast]
eProj v tproj =
  case (tproj, v) of
    (ProjPrim T.PrimInt, VPrimInt _) -> [v]
    (ProjPrim T.PrimChar, VPrimChar _) -> [v]
    (ProjPrim T.PrimUnit, VPrimUnit) -> [v]
    (ProjLabel n, VLabel n' _) | n == n' -> [v]
    (ProjFunc, VScape _ _) -> [v]
--    (T.TpFun, VFunc _ _) -> Just v
    (_, VOnion v1 v2) ->
      (eProj v2 tproj) ++ (eProj v1 tproj)
    _ -> []
