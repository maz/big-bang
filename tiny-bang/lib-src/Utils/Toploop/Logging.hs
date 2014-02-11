{-# LANGUAGE TupleSections #-}

{-|
  This module contains the parsing and configuration of CLI logging arguments
  for the interpreter.
-}

module Utils.Toploop.Logging
( Utils.Toploop.Logging.configureLogging
, configureLoggingInstruction
, Utils.Toploop.Logging.configureLoggingHandlers
) where

import Control.Applicative ((<$>))
import Data.List.Split
import System.Log
import System.Log.Formatter
import System.Log.Handler.Simple
import System.Log.Logger

import Language.TinyBang.Utils.Logger

-- | Configures logging from a set of logging level strings.  Returns True if
--   configuration was successful; returns False if something went wrong.  If
--   an error occurs, a message is printed before False is returned.
configureLogging :: [String] -> IO Bool
configureLogging configs =
  case mapM parseConfig configs of
    Left err -> do
      putStrLn $ "Logging configuration error: " ++ err
      return False
    Right steps -> do
      mapM_ configureLoggingInstruction steps
      return True

-- |Configures logging given the provided instruction.
configureLoggingInstruction :: LoggingInstruction -> IO ()
configureLoggingInstruction (loggerName, prio) =
  updateGlobalLogger loggerName $ setLevel prio
  
parseConfig :: String -> Either String LoggingInstruction
parseConfig str =
  let elems = splitOn ":" str in
  case elems of
    _:_:_:_ -> Left $ "Too many colons: " ++ str
    [] -> Left "Invalid logging configuration"
    [prioStr] ->
      (rootLoggerName,) <$> nameToPrio prioStr
    [name, prioStr] ->
      (name,) <$> nameToPrio prioStr
  where
    nameToPrio :: String -> Either String Priority
    nameToPrio prioStr =
      maybe (Left $ "Invalid priority: " ++ prioStr) Right $
        parsePriority prioStr

parsePriority :: String -> Maybe Priority
parsePriority prioStr =
  case prioStr of
    "debug" -> Just DEBUG
    "info" -> Just INFO
    "notice" -> Just NOTICE
    "warning" -> Just WARNING
    "error" -> Just ERROR
    "critical" -> Just CRITICAL
    "alert" -> Just ALERT
    "emergency" -> Just EMERGENCY
    _ -> Nothing

-- | Configures logging handlers for the interpreter.
configureLoggingHandlers :: IO ()
configureLoggingHandlers =
  updateGlobalLogger rootLoggerName $ setHandlers [handler]
  where
    handler = GenericHandler
      { priority = DEBUG
      , privData = ()
      , writeFunc = const putStrLn
      , closeFunc = const $ return ()
      , formatter = simpleLogFormatter "($prio): $msg"
      }
