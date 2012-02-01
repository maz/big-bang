{
{-# LANGUAGE BangPatterns #-}
-- The above pragma is a workaround inserted in the Alex source for this parser
-- to fix a bug in Alex 2.3.5.  Alex 2.3.5 uses bang patterns when -g is
-- enabled but does not set this language option.  Cabal uses Alex with -g, so
-- the above is necessary for source generated by Alex 2.3.5 to compile.
{-# OPTIONS_GHC -w #-}

module Language.TinyBang.Syntax.Lexer
( Token(..)
, lexTinyBang
, LexerResult
) where

import Control.Monad (liftM)

import Utils.Render.Display
}

%wrapper "monad"

$digit = 0-9
$lowerAlpha = [a-z]
$upperAlpha = [A-Z]
$alpha = [$lowerAlpha $upperAlpha]

tokens :-

    $white+                             ;
    `                                   { constTok TokLabelPrefix }
    &                                   { constTok TokOnionCons }
    \\                                  { constTok TokLambda }
    fun                                 { constTok TokFun }
    \->                                 { constTok TokArrow }
    case                                { constTok TokCase }
    of                                  { constTok TokOf }
    int                                 { constTok TokInteger }
    char                                { constTok TokChar }
-- TODO: TokUnit isn't actually used; remove it?
    unit                                { constTok TokUnit }
    \(                                  { constTok TokOpenParen }
    \)                                  { constTok TokCloseParen }
    \-?$digit+                          { strTok $ TokIntegerLiteral . read }
    \' ( \\. | ~\' ) \'                 { strTok $ TokCharLiteral . head . tail }
    \{                                  { constTok TokOpenBlock }
    \}                                  { constTok TokCloseBlock }
    \;                                  { constTok TokSeparator }
    _                                   { constTok TokUnder }
    :                                   { constTok TokColon }
    def                                 { constTok TokDef }
    \[\+\]                              { constTok TokOpPlus }
    \[\-\]                              { constTok TokOpMinus }
    \[\=\]                              { constTok TokOpEquals }
    \[\<\=\]                            { constTok TokOpLessEquals }
    \[\>\=\]                            { constTok TokOpGreaterEquals }
    \=                                  { constTok TokEquals }
    in                                  { constTok TokIn }
    \-int                               { constTok TokSubInteger }
    \-char                              { constTok TokSubChar }
    \-unit                              { constTok TokSubUnit }
    \-`                                 { constTok TokSubLabelPrefix }
    \-fun                               { constTok TokSubFun }
    $alpha [$alpha $digit _ ']*         { strTok $ TokIdentifier }

{
type LexerResult = Either String [Token]

lexTinyBang :: String -> LexerResult
lexTinyBang s = runAlex s tokenList
    where
        tokenLists = do
            tok <- alexMonadScan
            case tok of
                [] -> return []
                _ -> sequence [(return tok), tokenList]
        tokenList = liftM concat tokenLists

alexEOF :: Alex [Token]
alexEOF = return []

constTok :: a -> b -> c -> Alex [a]
constTok t = const $ const $ return [t]

strTok :: (String -> a) -> (b,c,String) -> Int -> Alex [a]
strTok f (_,_,s) len = return [f $ take len s]

data Token =
      TokLabelPrefix
    | TokOnionCons
    | TokLambda
    | TokFun
    | TokArrow
    | TokCase
    | TokOf
    | TokInteger
    | TokChar
    | TokUnit
    | TokUnder
    | TokOpenParen
    | TokCloseParen
    | TokIntegerLiteral Integer
    | TokCharLiteral Char
    | TokIdentifier String
    | TokOpenBlock
    | TokCloseBlock
    | TokSeparator
    | TokColon
    | TokDef
    | TokEquals
    | TokIn
    | TokOpPlus
    | TokOpMinus
    | TokOpEquals
    | TokOpLessEquals
    | TokOpGreaterEquals
    | TokSubInteger
    | TokSubChar
    | TokSubUnit
    | TokSubLabelPrefix
    | TokSubFun
    deriving (Eq, Show)

instance Display Token where
    makeDoc tok = text $ case tok of
        TokLabelPrefix -> "label prefix"
        TokOnionCons -> "onion constructor"
        TokLambda -> "lambda"
        TokFun -> "fun"
        TokArrow -> "arrow"
        TokCase -> "case"
        TokOf -> "of"
        TokInteger -> "int"
        TokChar -> "char"
        TokUnit -> "unit"
        TokUnder -> "underscore"
        TokOpenParen -> "open parenthesis"
        TokCloseParen -> "close parenthesis"
        TokIntegerLiteral _ -> "int literal"
        TokCharLiteral _ -> "char literal"
        TokIdentifier _ -> "identifier"
        TokOpenBlock -> "open block"
        TokCloseBlock -> "close block"
        TokSeparator -> "separator"
        TokColon -> "colon"
        TokDef -> "def"
        TokEquals -> "equals"
        TokIn -> "in"
        TokOpPlus -> "op plus"
        TokOpMinus -> "op minus"
        TokOpEquals -> "op equals"
        TokOpLessEquals -> "op less than or equal"
        TokOpGreaterEquals -> "op greater than or equal"
        TokSubInteger -> "-int"
        TokSubChar -> "-char"
        TokSubUnit -> "-unit"
        TokSubLabelPrefix -> "-`"
        TokSubFun -> "-fun"
}

