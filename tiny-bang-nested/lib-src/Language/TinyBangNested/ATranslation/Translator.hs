{- | 
  This module performs ATranslation to create a TinyBang Expr from a TinyBangNested Expr
-} 

module Language.TinyBangNested.ATranslation.Translator
(performTranslation)
where

import qualified Language.TinyBang.Ast.Data as TBA
import qualified Language.TinyBangNested.Ast.Data as TBN
import Language.TinyBang.Syntax.Location

import Language.TinyBangNested.ATranslation.TranslationState

import Data.Map 
import Data.Maybe

import Control.Applicative ((<$>))
import Control.Monad.State
import Control.Monad.Trans.Either


-- | Translation State Monad
type TransM = EitherT TransError (State TranslationState)

-- | Error type for translation
type TransError = String

-- | Utility methods for ATranslation
getFreshFlowVar :: TransM TBA.FlowVar
getFreshFlowVar = 
   do myState <- get
      modify incrementFlowVarCount
      return (TBA.FlowVar testOrigin ('x' : show (flowVarCount myState)))
     
getFreshCellVar :: TransM TBA.CellVar
getFreshCellVar = 
   do myState <- get
      modify incrementCellVarCount
      return (TBA.CellVar testOrigin ('y' : show (cellVarCount myState)))
     
cellVarLookup :: String -> TransM TBA.CellVar
cellVarLookup varName = 
  do myState <- get
     if isNothing $ lookUp $ varMap myState
       then transformError $ "variable " ++ varName ++ " undefined."
       else return $ fromJust $ lookUp $ varMap myState
         where lookUp = Data.Map.lookup varName
               
insertVar :: String -> TBA.CellVar -> TransM ()
insertVar varName cell =
  do (TranslationState _ _ m) <- get
     let newMap = insert varName cell m
     modify $ updateMap newMap
       
transformError :: TransError -> TransM a
transformError transError = left $ "Translation error: " ++  transError

-- | Begin translation for expressions

-- | Computed type for expression evaluation
type TExprValue = ([TBA.Clause], TBA.FlowVar)

-- | aTransformExpr recurses over a TBN.Expr, updating the TransM state monad as it goes
-- | with the resulting [Clause] in the state representing the final TBA.Expr translation.
aTransformExpr :: TBN.Expr -> TransM TExprValue
aTransformExpr expr =
  case expr of
    TBN.ExprDef org (TBN.Var _ varName) e1 e2 ->
      do (TranslationState _ _ savedMapState) <- get
         (varValueCls, varClsFlow) <- aTransformExpr e1
         cellForDefVar <- getFreshCellVar
         let varDefCls = [genClauseCellDef org cellForDefVar varClsFlow]
         insertVar varName cellForDefVar
         (exprValueCls, resultFlow) <- aTransformExpr e2
         (TranslationState x y _) <- get
         put (TranslationState x y savedMapState)
         return (varValueCls ++ varDefCls ++ exprValueCls, resultFlow)
         
    TBN.ExprVarIn org (TBN.Var _ varName) e1 e2 ->
      do (varValueCls, varClsFlow) <- aTransformExpr e1
         cellForSetVar <- cellVarLookup varName
         let varSetCls = [genClauseCellSet org cellForSetVar varClsFlow]
         (exprValueCls, resultFlow) <- aTransformExpr e2
         return (varValueCls ++ varSetCls ++ exprValueCls, resultFlow)
         
    TBN.ExprScape org pattern e ->
      do (TranslationState _ _ savedMapState) <- get
         p <-  aTransformOuterPattern pattern
         (cls, _) <- aTransformExpr e
         (TranslationState x y _ ) <- get
         put (TranslationState x y savedMapState)
         freshFlow <- getFreshFlowVar
         let scapeExpr = TBA.Expr org cls
         let scapeClause = [genClauseScape org freshFlow p scapeExpr]
         return (scapeClause, freshFlow)
         
    TBN.ExprBinaryOp org e1 op e2 ->
      do (leftCls, leftFlow) <- aTransformExpr e1
         (rightCls, rightFlow) <- aTransformExpr e2
         freshFlow <- getFreshFlowVar
         return (leftCls ++ rightCls ++ [genClauseBinOp org freshFlow leftFlow op rightFlow]
                , freshFlow)
           
    TBN.ExprOnionOp org e op proj ->
      do (cls, v) <- aTransformExpr e
         freshFlow <- getFreshFlowVar
         return (cls ++ [genClauseValueDef org freshFlow (genOnionFilterValue org v op proj)]
                , freshFlow)
           
    TBN.ExprOnion org e1 e2 ->
      do (leftCls, leftFlow) <- aTransformExpr e1
         (rightCls, rightFlow) <- aTransformExpr e2
         freshFlow <- getFreshFlowVar
         return (leftCls ++ rightCls ++ [genClauseOnion org freshFlow leftFlow rightFlow]
                , freshFlow)
           
    TBN.ExprAppl org e1 e2 ->
      do (leftCls, leftFlow) <- aTransformExpr e1
         (rightCls, rightFlow) <- aTransformExpr e2
         freshFlow <- getFreshFlowVar
         return (leftCls ++ rightCls ++ [genClauseAppl org freshFlow leftFlow rightFlow]
                , freshFlow)
           
    TBN.ExprLabelExp org l e1 ->
      do (cls, v) <- aTransformExpr e1
         freshFlow <- getFreshFlowVar
         freshCell <- getFreshCellVar
         return (cls ++ [ genClauseCellDef org freshCell v
                        , genClauseValueDef org freshFlow (genLabelValue l freshCell)
                        ]
                , freshFlow)
  
    TBN.ExprVar org (TBN.Var _ varName) ->
      do freshFlow <- getFreshFlowVar
         cellVar <- cellVarLookup varName
         return ([genClauseCellGet org freshFlow cellVar], freshFlow)
         
    TBN.ExprValInt org i ->
      do freshFlow <- getFreshFlowVar
         return ([genClauseValueDef org freshFlow (TBA.VInt org i)], freshFlow)
         
    TBN.ExprValChar org c ->
      do freshFlow <- getFreshFlowVar
         return ([genClauseValueDef org freshFlow (TBA.VChar org c)], freshFlow)

    TBN.ExprValUnit org ->
      do freshFlow <- getFreshFlowVar
         return ([genClauseValueDef org freshFlow (TBA.VEmptyOnion org)], freshFlow)

-- | Begin translation for patterns

-- OuterPattern ::= Var : Pattern
aTransformOuterPattern :: TBN.OuterPattern -> TransM TBA.Pattern
aTransformOuterPattern pat =
  case pat of
    TBN.OuterPatternLabel org (TBN.Var _ varName) innerpat -> 
      do cellVar <- getFreshCellVar
         insertVar varName cellVar
         transformedPat <- aTransformInnerPattern innerpat
         return (TBA.ValuePattern org cellVar transformedPat)
         
-- Pattern ::= Pattern & Pattern
-- Pattern ::= Label Var : Pattern
-- Pattern ::= Primitive
-- Pattern ::= fun
-- Pattern ::= ()
aTransformInnerPattern :: TBN.Pattern -> TransM TBA.InnerPattern
aTransformInnerPattern pat =
  case pat of
    TBN.ConjunctionPattern org p1 p2 ->
      do innerPat1 <- aTransformInnerPattern p1
         innerPat2 <- aTransformInnerPattern p2
         return $ TBA.ConjunctionPattern org innerPat1 innerPat2
            
      
    TBN.LabelPattern org (TBN.LabelDef labelOrg str) (TBN.Var _ varName) pattern ->
      do cellVar <- getFreshCellVar
         insertVar varName cellVar
         innerPat <- aTransformInnerPattern pattern
         return $ TBA.LabelPattern org (TBA.LabelName labelOrg str) cellVar innerPat
         
    TBN.PrimitivePattern org prim -> 
      return (TBA.PrimitivePattern org $ primType prim)
        where primType ::TBN.Primitive -> TBA.PrimitiveType
              primType p = 
                case p of
                  TBN.TInt o -> TBA.PrimInt o
                  TBN.TChar o -> TBA.PrimChar o

    TBN.ScapePattern org ->
      return (TBA.ScapePattern org)
      
    TBN.EmptyOnionPattern org ->
      return (TBA.EmptyOnionPattern org)


-- | Clause generators for use in above translations

genClauseBinOp :: TBA.Origin -> TBA.FlowVar -> TBA.FlowVar 
               -> TBN.BinaryOperator -> TBA.FlowVar  -> TBA.Clause
genClauseBinOp org flow leftFlow op rightFlow = 
  TBA.RedexDef org flow (TBA.BinOp org leftFlow binop rightFlow)
    where binop = 
           case op of
             TBN.OpPlus o -> TBA.OpPlus o
             TBN.OpMinus o -> TBA.OpMinus o
             TBN.OpEqual o -> TBA.OpEqual o
             TBN.OpLesser o -> TBA.OpLess o  
             TBN.OpGreater o -> TBA.OpGreater o
             _ -> error $ "Interpreter does not support " ++ show binop

genClauseValueDef :: TBA.Origin -> TBA.FlowVar -> TBA.Value -> TBA.Clause
genClauseValueDef org flow value = TBA.Evaluated (TBA.ValueDef org flow value)
        
genClauseOnion :: TBA.Origin -> TBA.FlowVar -> TBA.FlowVar -> TBA.FlowVar -> TBA.Clause
genClauseOnion org fnew f1 f2 = genClauseValueDef org fnew (TBA.VOnion org f1 f2)

genClauseScape :: TBA.Origin -> TBA.FlowVar -> TBA.Pattern -> TBA.Expr -> TBA.Clause
genClauseScape org flow pat expr = genClauseValueDef org flow (TBA.VScape org pat expr)

genClauseAppl :: TBA.Origin -> TBA.FlowVar -> TBA.FlowVar -> TBA.FlowVar -> TBA.Clause
genClauseAppl org flow f1 f2 = TBA.RedexDef org flow (TBA.Appl org f1 f2)

genClauseCellGet :: TBA.Origin  -> TBA.FlowVar -> TBA.CellVar -> TBA.Clause
genClauseCellGet = TBA.CellGet

genClauseCellSet :: TBA.Origin -> TBA.CellVar -> TBA.FlowVar -> TBA.Clause
genClauseCellSet  = TBA.CellSet

genClauseCellDef :: TBA.Origin -> TBA.CellVar -> TBA.FlowVar -> TBA.Clause
genClauseCellDef org cell flow  = TBA.Evaluated (TBA.CellDef org (TBA.QualNone org) cell flow)

genLabelValue :: TBN.Label -> TBA.CellVar -> TBA.Value 
genLabelValue (TBN.LabelDef o s) cell =  TBA.VLabel o (TBA.LabelName o s) cell 

genOnionFilterValue :: TBA.Origin -> TBA.FlowVar -> TBN.OnionOperator -> TBN.Projector -> TBA.Value
genOnionFilterValue org v op proj = 
     TBA.VOnionFilter org v convertOp convertProj
       where
         convertOp :: TBA.OnionOp
         convertOp = case op of 
           TBN.OpOnionSub o -> TBA.OpOnionSub o
           TBN.OpOnionProj o -> TBA.OpOnionProj o
         convertProj :: TBA.AnyProjector
         convertProj = case proj of
           TBN.PrimitiveProjector o p -> TBA.SomeProjector $ TBA.ProjPrim o (convertPrim p)
           TBN.LabelProjector o (TBN.LabelDef labelOrg s) -> 
             TBA.SomeProjector $ TBA.ProjLabel o (TBA.LabelName labelOrg s)
           TBN.FunProjector o -> TBA.SomeProjector $ TBA.ProjFun o
         convertPrim :: TBN.Primitive -> TBA.PrimitiveType
         convertPrim p = case p of
           TBN.TInt o -> TBA.PrimInt o
           TBN.TChar o -> TBA.PrimChar o        

-- | Setup state for performTransformation:
           
testLocation :: SourceRegion
testLocation = SourceRegion Unknown Unknown

testOrigin :: TBA.Origin
testOrigin = TBA.SourceOrigin testLocation

startState :: TranslationState
startState = TranslationState 0 0 empty

performTranslation :: TBN.Expr -> Either TransError TBA.Expr
performTranslation expr = TBA.Expr testOrigin <$> fst <$> evalState (runEitherT $ aTransformExpr expr) startState