{-|
  Defines the tokens used in the TinyBang parser.
-}

module Language.TinyBang.Syntax.Tokens
( Token(..)
, PositionalToken(..)
) where

import Language.TinyBang.Syntax.Location
import Language.TinyBang.Utils.Display

-- |The raw tokens generated by this lexer.
data Token
  = TokIs -- ^@=@
  | TokArrow -- ^@->@
  | TokStartBlock -- ^@{@
  | TokStopBlock -- ^@}@
  | TokEmptyOnion -- ^@()@
  | TokOnion -- ^@&@
  | TokInt -- ^@int@
  | TokOpenParen -- ^@(@
  | TokCloseParen -- ^@)@
  | TokSemi -- ^@;@
  | TokIdentifier String
  | TokLitInt Integer
  | TokLabel String -- ^The @String@ is only the name of the label, not the @`@
  | TokPlus -- ^@+@
  | TokMinus -- ^@-@
  | TokEq -- ^@==@
  | TokLessEq -- ^@<=@
  | TokGreaterEq -- ^@>=@
  | TokSet -- ^@<-@
  | TokRef -- ^@ref@
  deriving (Eq, Ord, Show)

-- |An annotation for tokens which describes their source position.
data PositionalToken
  = PositionalToken { startPos :: DocumentPosition
                    , stopPos :: DocumentPosition
                    , posToken :: Token }
  deriving (Eq, Ord, Show)

instance HasDocumentStartStopPositions PositionalToken where
  documentStartPositionOf = startPos
  documentStopPositionOf = stopPos
  
instance Display Token where
  makeDoc t = case t of
    TokIs -> dquotes $ text "="
    TokEmptyOnion -> dquotes $ text "()"
    TokOnion -> dquotes $ text "&"
    TokArrow -> dquotes $ text "->"
    TokInt -> dquotes $ text "int"
    TokOpenParen -> dquotes $ text "("
    TokCloseParen -> dquotes $ text ")"
    TokSemi -> dquotes $ text ";"
    TokStartBlock -> dquotes $ text "{"
    TokStopBlock -> dquotes $ text "}"
    TokIdentifier s -> text "id#" <> dquotes (text s)
    TokLitInt n -> text "int#" <> dquotes (text $ show n)
    TokLabel n -> text "label#" <> dquotes (text n)
    TokPlus -> text "+"
    TokMinus -> text "-"
    TokEq -> text "=="
    TokLessEq -> text "<="
    TokGreaterEq -> text ">="
    TokSet -> text "<-"
    TokRef -> text "ref"

instance Display PositionalToken where
  makeDoc pt =
    makeDoc (posToken pt) <+> text "at" <+>
      makeDoc (startPos pt) <> char '-' <> makeDoc (stopPos pt)
