{-|
  This module loads the source file tests.
-}
module Test.PatBang.SourceFile
( sourceFileTests
) where

import Data.List
import Data.List.Split (splitOn)
import System.Directory
import System.FilePath
import Test.HUnit

import Language.PatBang.Ast
import Language.PatBang.Display
import Language.PatBang.Interpreter
import Language.PatBang.Interpreter.DeepValues
import Language.PatBang.Syntax.Lexer
import Language.PatBang.Syntax.Location
import Language.PatBang.Syntax.Parser
import Language.PatBang.TypeSystem.ConstraintDatabase.Simple
import Language.PatBang.TypeSystem.TypeInference
import Test.PatBang.ExpectDsl

testsPath :: FilePath
testsPath = "tests"

sourceFileTests :: IO Test
sourceFileTests = do
  dirContents <- getDirectoryContents testsPath
  let paths = map ((testsPath ++ [pathSeparator]) ++) $
                filter (isSuffixOf ".pb") dirContents
  mtests <- mapM makeTestFromPath paths
  return $
    case sequence mtests of
      Left err -> TestCase $ assertString $ "Test construction failure: " ++ err 
      Right tests -> TestList tests
  where
    makeTestFromPath :: FilePath -> IO (Either String Test)
    makeTestFromPath filepath = do
      source <- readFile filepath
      -- get the possible expectations
      let mexpectations = map toExpectation $ splitOn "\n" source
      -- filter out acceptable errors
      let mexpectations' = sequence $
            filter (\x->case x of {Left NoExpectationFound -> False; _ -> True})
              mexpectations
      -- if there are still errors, report them
      case mexpectations' of
        Left noExpectation -> case noExpectation of
          NoExpectationFound ->
            error "Test.PatBang.SourceFile: didn't we just filter this out?"
          BadExpectationParse src err ->
            return $ Left $ filepath ++ ": could not parse expectation " ++ src
              ++ ": " ++ err
        Right expectations -> case expectations of
          [] -> return $ Left $ filepath ++ ": no expectation found"
          _:_:_ -> return $ Left $ filepath ++ ": multiple expectations found"
          [expectation] -> return $ case lexPatBang filepath source of
            Left err -> Left $ filepath ++ ": Lexer failure: " ++ err
            Right tokens ->
              let context = ParserContext
                    { contextDocument = UnknownDocument -- TODO: fix
                    , contextDocumentName = filepath
                    } in
              case parsePatBang context tokens of
                Left err -> Left $ filepath ++ ": Parser failure: " ++ err
                Right ast -> Right $ createTest filepath expectation ast
    toExpectation :: String -> Either NoExpectation Expectation
    toExpectation str =
      case afterPart "# EXPECT:" str of
        Just src ->
          let src' = trim src in
          case parseExpectDslPredicate src' of
            Left err -> Left $ BadExpectationParse src' err
            Right expectation -> Right expectation
        Nothing -> Left NoExpectationFound
    trim :: String -> String
    trim str = reverse $ trimFront $ reverse $ trimFront str
      where
        trimFront :: String -> String
        trimFront = dropWhile (== ' ')
    afterPart :: String -> String -> Maybe String
    afterPart pfx str = if pfx `isPrefixOf` str
                          then Just $ drop (length pfx) str
                          else Nothing
    createTest :: FilePath -> Expectation -> Expr -> Test
    createTest filepath expectation expr =
      let tcResult = typecheck expr
          tcResult :: Either (TypecheckingError SimpleConstraintDatabase)
                        SimpleConstraintDatabase
      in
      let result = eval expr in
      case expectation of
        Pass predicate predSrc -> TestLabel filepath $ TestCase $
          case (tcResult, result) of
            (Left err, _) ->
              assertString $ "Expected " ++ display predSrc
                ++ " but type error occurred: " ++ display err
            (_, Left (err,_)) ->
              assertString $ "Expected " ++ display predSrc
                ++ " but error occurred: " ++ display err
            (_, Right (env,var)) ->
              let monion = deepOnion (flowVarMap env) var in
              case monion of
                Left failure ->
                  error $ "Evaluator produced a result which did not " ++ 
                          "convert to an onion!  " ++ display failure
                Right onion ->
                  assertBool ("Expected " ++ display predSrc
                      ++ " but evaluation produced: " ++ display onion) $
                    predicate onion
        TypeFailure -> TestLabel filepath $ TestCase $
          case tcResult of
            Left _ -> assert True
            Right db ->
              assertString $ "Expected type failure but typechecking produced "
                          ++ "a valid database: " ++ display db

data NoExpectation
  = NoExpectationFound
  | BadExpectationParse
      String -- ^ The source string for the predicate.
      String -- ^ The error message from the lexer/parser.
  deriving (Eq, Ord, Show)
