{
{-# LANGUAGE BangPatterns #-}
-- The above pragma is a workaround inserted in the Alex source for this parser
-- to fix a bug in Alex 2.3.5.  Alex 2.3.5 uses bang patterns when -g is
-- enabled but does not set this language option.  Cabal uses Alex with -g, so
-- the above is necessary for source generated by Alex 2.3.5 to compile.
{-# OPTIONS_GHC -w #-}

module Language.LittleBang.Syntax.Lexer
( Token(..)
, lexLittleBang
, LexerResult
) where

import Control.Monad (liftM)
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
    unit                                { constTok TokUnit }
    \(                                  { constTok TokOpenParen }
    \)                                  { constTok TokCloseParen }
    \-?$digit+                          { strTok $ TokIntegerLiteral . read }
    \' ( \\. | ~\' ) \'                 { strTok $ TokCharLiteral . head . tail }
    $alpha [$alpha $digit _ ']*         { strTok $ TokIdentifier }
    \{                                  { constTok TokOpenBlock }
    \}                                  { constTok TokCloseBlock }
    \;                                  { constTok TokSeparator }
    _                                   { constTok TokUnder }
    :                                   { constTok TokColon }

{
type LexerResult = Either String [Token]

lexLittleBang :: String -> LexerResult
lexLittleBang s = runAlex s tokenList
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
    deriving (Eq, Show)
}
    
