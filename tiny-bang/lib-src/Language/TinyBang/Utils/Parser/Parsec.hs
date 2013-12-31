{-# LANGUAGE TemplateHaskell #-}

{-|
  This module contains some simple Parsec utilities.  Most notably, it contains
  "commit" operators @?=>@ and @?+>@ which are meant to be used with e.g.
  @<*>@ to create a more BNF-style syntax.
-}
module Language.TinyBang.Utils.Parser.Parsec
( packrat
, (</>)
, ($%)
, conditional
, (<@>)
, conditionalDiscard
, (?=>)
, eps
, (?+>)
) where

import Control.Applicative ((<*),(<*>))
import Text.Parsec.Prim

import Language.TinyBang.Utils.Display hiding ((</>))
import Language.TinyBang.Utils.Logger

$(loggingFunctions)

-- |A binary packrat parser operation.  The first parser is attempted; if it
--  fails, it consumes no input and the second parser is used instead.
packrat :: ParsecT s u m a -> ParsecT s u m a -> ParsecT s u m a
packrat a b = try a <|> b

-- |An infix alias for @packrat@.
(</>) :: ParsecT s u m a -> ParsecT s u m a -> ParsecT s u m a
(</>) = packrat
infixl 1 </>

-- |A binary operator for application.  This is equivalent to '$' but has an
--  infix priority of higher than that of @<|>@ and @</>@, thus making it useful
--  for writing BNF-like code.
($%) :: (a -> b) -> a -> b
($%) = ($)
infixr 2 $%

-- |A combinator which is used for conditional parsing.  This function takes a
--  parser producing a function and another parser producing the argument of
--  that function.  If the first parser does not match, the entire parser
--  consumes no input.  If the first parser does match, the parse is committed
--  and the second parser is used to produce an argument for the function
--  generated by the first parser.
conditional :: ParsecT s u m (a -> b) -> ParsecT s u m a -> ParsecT s u m b
conditional a b = try a <*> b

-- |An infix alias for @conditional@.  This operator is at the same fixity as
--  @<$>@ and @<*>@ so it can be used in sequences.
(?=>) :: ParsecT s u m (a -> b) -> ParsecT s u m a -> ParsecT s u m b
(?=>) = conditional
infixl 4 ?=>

-- |A form of @conditional@ which does not expect a useful argument to its
--  immediate right.  Instead, the second parser's argument is discarded.
conditionalDiscard :: ParsecT s u m a -> ParsecT s u m b -> ParsecT s u m a
conditionalDiscard a b = try a <* b

-- |An infix alias for @conditionalDiscard@.  @?+>@ is to @<*@ as @?=>@ is to
--  @<*>@.
(?+>) :: ParsecT s u m a -> ParsecT s u m b -> ParsecT s u m a
(?+>) = conditionalDiscard
infixl 4 ?+>

-- |A parser which always succeeds, returning unit.  This is equivalent to
--  @return ()@.  It is particularly useful as an alternative to @try@
--  expressions: @try (foo <$> bar <*> baz)@ is equivalent to
--  @foo <$> bar <*> baz ?+> eps@.  (@eps@ is short for "epsilon").
eps :: ParsecT s u m ()
eps = return ()

-- |Wraps a parser in a debug logger.  This logger will log messages when the
--  parser starts, succeeds, or fails.  The first argument to this function is
--  a description of the parser in question.
loggingParser :: (Monad m, Display a)
              => String -> ParsecT s u m a -> ParsecT s u m a
loggingParser desc p = do
  st <- getParserState
  result <- _debugI ("Trying " ++ desc ++ " at "  ++ show (statePos st)) $
                  p
              <|> _debugI ("Failed to parse " ++ desc ++ " at "
                            ++ show (statePos st)) parserZero
  _debugI ("Parsed " ++ desc ++ " at " ++ show (statePos st) ++ ": " ++
            display result) $
    return result
  
-- |An infix synonym for @loggingParser@.
(<@>) :: (Monad m, Display a) => String -> ParsecT s u m a -> ParsecT s u m a
(<@>) = loggingParser
infixl 0 <@>
