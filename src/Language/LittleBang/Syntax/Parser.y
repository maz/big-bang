{
{-# OPTIONS_GHC -w #-}

module Language.LittleBang.Syntax.Parser
( parseLittleBang
, ParseError
, ParseM
) where

import Control.Monad.Error (ErrorT, runErrorT, Error, strMsg, throwError)
import Control.Monad.Identity (Identity, runIdentity)
import Data.Maybe (listToMaybe)

import qualified Language.LittleBang.Ast as A
import Language.LittleBang.Render.Display
import qualified Language.LittleBang.Syntax.Lexer as L
import qualified Language.LittleBang.Types.Types as T
import Language.LittleBang.Types.UtilTypes
    ( Ident
    , ident
    , unIdent
    , LabelName
    , labelName
    , unLabelName
    )

-- For debugging purposes only
import System.IO.Unsafe
import System.IO
}

%name doParseLittleBang
%tokentype { L.Token }
%error { parseError }
%monad { ParseM } { (>>=) } { return }

%token
        '`'             { L.TokLabelPrefix }
        '&'             { L.TokOnionCons }
        '\\'            { L.TokLambda }
        fun             { L.TokFun }
        '->'            { L.TokArrow }
        case            { L.TokCase }
        of              { L.TokOf }
        int             { L.TokInteger }
        char            { L.TokChar }
        unit            { L.TokUnit }
        '('             { L.TokOpenParen }
        ')'             { L.TokCloseParen }
        intLit          { L.TokIntegerLiteral $$ }
        charLit         { L.TokCharLiteral $$ }
        ident           { L.TokIdentifier $$ }
        '{'             { L.TokOpenBlock }
        '}'             { L.TokCloseBlock }
        ';'             { L.TokSeparator }
        '_'             { L.TokUnder }
        ':'             { L.TokColon }

%right      '->'
%right      '&'

%%

Exp     :   '\\' ident '->' Exp
                                    { A.Func (ident $2) $4 }
        |   fun ident '->' Exp
                                    { A.Func (ident $2) $4 }
        |   case Exp of '{' Branches '}'
                                    { A.Case $2 $5 }
        |   Exp '&' Exp
                                    { A.Onion $1 $3 }
        |   ApplExp
                                    { $1 }


ApplExp :   ApplExp Primary
                                    { A.Appl $1 $2 }
        |   Primary
                                    { $1 }


Primary :   ident
                                    { A.Var (ident $1) }
        |   intLit
                                    { A.PrimInt $1 }
        |   charLit
                                    { A.PrimChar $1 }
        |   '(' ')'
                                    { A.PrimUnit }
        |   '`' ident Primary
                                    { A.Label (labelName $2) $3 }
        |   '(' Exp ')'
                                    { $2 }


Branches:   Branch ';' Branches     { $1:$3 }
        |   Branch                  { [$1] }


Branch  :   Pattern '->' Exp        
                                    { A.Branch Nothing $1 $3 }
        |   ident ':' Pattern '->' Exp
                                    { A.Branch (Just $ ident $1) $3 $5 }


Pattern :   PrimitiveType           { A.ChiPrim $1 }
        |   '`' ident ident         { A.ChiLabel (labelName $2) (ident $3) }
        |   fun                     { A.ChiFun }
        |   '_'                     { A.ChiTop }


PrimitiveType
        :   int                     { T.PrimInt }
        |   char                    { T.PrimChar }
        |   unit                    { T.PrimUnit }


{
data ParseError
        = ParseError [L.Token]
instance Error ParseError where
    strMsg = error
instance Display ParseError where
    makeDoc err =
            let desc = case err of
                        ParseError tokens ->
                            maybe "<EOS>" display $ listToMaybe tokens
            in text "unexpected" <+> text desc <+> text "token"
instance Show ParseError where
    show = display

type ParseM a = ErrorT ParseError Identity a

parseError :: [L.Token] -> ParseM a
parseError = throwError . ParseError

parseLittleBang :: [L.Token] -> Either ParseError A.Expr
parseLittleBang tokens =
    runIdentity $ runErrorT $ doParseLittleBang tokens
}