module Language.TinyBang.Test.Functions
( tests
)
where

import Language.TinyBang.Test.UtilFunctions
import Language.TinyBang.Test.NameUtils
  ( idX
  )
import Language.TinyBang.Test.ExpressionUtils
  ( varX
  )
import Language.TinyBang.Test.ValueUtils
  ( identFuncX
  )
import Language.TinyBang.Test.SourceUtils
  ( srcY
  , srcMultiAppl
  )

import qualified Language.TinyBang.Ast as A
import qualified Language.TinyBang.Config as Cfg
import qualified Language.TinyBang.Interpreter.Ast as IA
import Utils.Language.Ast

tests :: (?conf :: Cfg.Config) => Test
tests = TestLabel "Test functions" $ TestList
  [ xEval "x -> x"
          identFuncX
  , xEval "(x -> x) (x -> x)"
          identFuncX
  , xEval "(y -> y) (x -> x)"
          identFuncX
  , xEval "def x = x -> x in x x"
          identFuncX
  , xType srcY
  , xEval "x -> x x"
      (A.VScape (A.Pattern idX $ A.PatOnion []) $
      (astwrap $ A.Appl varX varX :: IA.Expr))
  , xType "(x -> x x) (x -> x x)"
  , xType "def omega = x -> x x in omega omega"

  -- Ensure that functions are correctly polymorphic when stored in cells
  , xType "def f = (x -> x) in (f 1) & (f ())"

  -- Ensure that constraints propogate into functions properly
  , xCont "(f -> f ()) (x -> 1 + x)"
  , xCont "(x -> x + 1) 'a'"

  -- Test that application requires that the first argument be a function
  , xCont "1 'x'"

  -- Ensure that constraints from functions propagate correctly from cells
  , xCont "def f = (x:int -> x ) in (f 1) & (f ())"

  -- Test typechecking of some pathological functions
  , xType $ srcMultiAppl
      [srcY, "this -> x -> this (`A x & `B x)"]
  , xType $ srcMultiAppl
      [srcY, "this -> x -> this (`A x & `B x)", "0"]
  , xType $ srcMultiAppl
      [srcY, "this -> x -> this (`A x & `B x)", "()"]
  , xType $ srcMultiAppl
      [srcY, "this -> x -> this (`A x & `B x)", "`A () & `B ()"]
  , xType $ srcMultiAppl
      [srcY, "this -> x -> this (`A x & `B x)", srcY]

  -- Check that variable closed-ness works in functions
  , xNotC "(x -> n + 2)"
--   , xPars "fun x -> case x of {`True a -> 1; `False a -> 0}"
--           (astwrap $ A.Func idX $ astwrap $
--               A.Case varX
--                      [ A.Branch
--                         (A.ChiTopBind $ A.ChiUnbound $
--                               (A.ChiLabelShallow (labelName "True")
--                                           (ident "a")))
--                               (astwrap $ A.PrimInt 1)
--                      , A.Branch
--                         (A.ChiTopBind $ A.ChiUnbound $
--                               (A.ChiLabelShallow (labelName "False")
--                                           (ident "a")))
--                               (astwrap $ A.PrimInt 0)
--                      ])
   ]
