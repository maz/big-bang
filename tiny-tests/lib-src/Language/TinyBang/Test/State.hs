module Language.TinyBang.Test.State
( tests
)
where

import Language.TinyBang.Test.UtilFunctions
import qualified Language.TinyBang.Ast as A
import qualified Language.TinyBang.Config as Cfg
import qualified Language.TinyBang.Interpreter.Ast as IA
import Utils.Language.Ast

idX = ident "x"
varX :: A.Expr
varX = astwrap $ A.Var idX

efour :: A.Expr
efour = astwrap $ A.PrimInt 4
four :: A.Value IA.Expr
four = A.VPrimInt 4
two :: A.Value IA.Expr
two = A.VPrimInt 2

tests :: (?conf :: Cfg.Config) => Test
tests = TestLabel "State tests" $ TestList
  [ xPars "def x = 4 in x" $
          astwrap $ A.Def Nothing idX efour varX
  , xPars "x = 4 in x" $
          astwrap $ A.Assign idX efour varX
  , xPars "def x = 4 in x & 'a'" $
          astwrap $ A.Def Nothing idX efour $ astwrap $
            A.Onion varX $ astwrap $ A.PrimChar 'a'
  , xPars "x = 4 in x & 'a'" $
          astwrap $ A.Assign idX efour $ astwrap $
            A.Onion varX $ astwrap $ A.PrimChar 'a'
  , xPars "def x = 3 in x = 4 in x" $
          astwrap $ A.Def Nothing idX (astwrap $ A.PrimInt 3) $ astwrap $
            A.Assign idX efour varX

  -- Test evaluation of definition and assignment
  , xEval "def x = 4 in x" four
  , xNotC "x = 4 in x"
  , xEval "def x = 3 in x = 4 in x" four
  , xEval "def x = () in x = 4 in x" four
  , xEval "def x = () in case x of { unit -> 4 }" four

  -- Test that def can be encoded with case.
  , xEval "case `Ref 4 of {`Ref x -> x = 2 in x}" two

  -- The next two tests are contradictions due to flow insensitivity.
  , xCont "def x = () in x = 2 in case x of { unit -> 4 }"
  , xCont "def x = () in x = 2 in case x of { int -> 4 }"
  , xEval "def x = () in x = 2 in case x of { unit -> 2 ; int -> 4 }" four

  -- TODO: add unit tests for finality and immutability
  ]
