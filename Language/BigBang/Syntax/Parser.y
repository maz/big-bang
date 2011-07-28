{
{-# OPTIONS_GHC -w #-}

module Language.BigBang.Syntax.Parser
( parseBigBang
) where

import qualified Language.BigBang.Ast as A
import qualified Language.BigBang.Syntax.Lexer as L
import qualified Language.BigBang.Types.Types as T
import Language.BigBang.Types.UtilTypes
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

%name parseBigBang
%tokentype { L.Token }
%error { parseError }

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


Branch  :   Pattern '->' Exp        { ($1,$3) }


Pattern :   PrimitiveType           { A.ChiPrim $1 }
        |   '`' ident ident         { A.ChiLabel (labelName $2) (ident $3) }
        |   fun                     { A.ChiFun }
        |   '_'                     { A.ChiTop }


PrimitiveType
        :   int                     { T.PrimInt }
        |   char                    { T.PrimChar }
        |   unit                    { T.PrimUnit }


{
parseError :: [L.Token] -> a
parseError _ = error "Parse error"
}
