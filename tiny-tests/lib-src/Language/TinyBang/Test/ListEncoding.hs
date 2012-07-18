module Language.TinyBang.Test.ListEncoding
( tests
)
where

import Language.TinyBang.Test.UtilFunctions
import Language.TinyBang.Test.SourceUtils
import qualified Language.TinyBang.Config as Cfg
import qualified Language.TinyBang.Test.ValueUtils as V
import Text.Printf (printf)

srcMakeList :: [Integer] -> TinyBangCode
srcMakeList = foldr addNode "`nil ()"
  where addNode int tbCode =
          printf "`hd %d & (`tl (%s))" int tbCode

-- Observe that, in the following, the inner `nil branch is never possible
-- and is never taken; it's just here for the (path-insensitive) typechecker.

srcSum1 =
  tbScape ["this", "xs"] $
  tbCase "xs" [ tbScape ["`nil _"] "0"
              , tbScape ["`hd a"] $
                  tbCase "xs" ["`tl b -> a + this b"
                              ,"`nil _ -> 0"]]

-- srcSum1 = "fun this -> fun xs ->                                    \
--           \ case xs of                                              \
--           \ { `nil junk -> 0 ;                                      \
--           \   `hd a -> case xs of                                   \
--           \       {`tl b -> a + (this b);                           \
--           \        `nil _ -> 0}                                     \
--           \ }                                                       "

srcSum2 =
  tbScape ["this", "accum", "xs"] $
  tbCase "xs" [ tbScape ["`nil _"] "accum"
              , tbScape ["`hd a"] $
                  tbCase "xs" ["`tl b -> this (a + accum) b"
                              ,"`nil _ -> accum"]]

-- srcSum2 = "fun this -> fun accum -> fun xs ->                       \
--           \ case xs of                                              \
--           \ { `nil junk -> accum ;                                  \
--           \   `hd a -> case xs of                                   \
--           \       {`tl b -> this (a + accum) b;                     \
--           \        `nil _ -> accum}                                 \
--           \ }                                                       "

srcSum3 =
  tbScape ["this", "xs"] $
  tbCase "xs" [ tbScape ["`acc accum"] $
    tbCase "xs" [ tbScape ["`nil _"] "accum"
                , tbScape ["`hd a"] $
                    tbCase "xs" ["`tl b -> this (b & `acc (a + accum))"
                                ,"`nil _ -> accum"]]]

-- srcSum3 = "fun this -> fun xs ->                                    \
--           \ case xs of { `acc accum ->                              \
--           \ case xs of                                              \
--           \ { `nil junk -> accum;                                   \
--           \   `hd a -> case xs of                                   \
--           \       {`tl b -> this (b & `acc (a + accum));          \
--           \        `nil _ -> accum}                                 \
--           \ }}                                                      "

srcSum4 =
  tbDef "accum" "0" $
  tbScape ["this", "xs"] $
  tbCase "xs" [ tbScape ["`nil _"] "accum"
              , tbScape ["`hd a"] $
                  tbCase "xs" [ tbScape ["`tl b"] $
                                  tbAssign "accum" "accum + a" "this b"
                              , tbScape ["`nil _"] "accum"]]

-- srcSum4 = "def accum = 0 in fun this -> fun xs ->                   \
--           \ case xs of                                              \
--           \ { `nil junk -> accum;                                   \
--           \   `hd a -> case xs of                                   \
--           \       {`tl b -> accum = accum + a in this b ;           \
--           \        `nil _ -> accum}                                 \
--           \ }                                                       "

srcFoldl =
  tbScape ["this", "f", "z", "xs"] $
  tbCase "xs" [ tbScape ["`nil _"] "z"
              , tbScape ["`hd a"] $
                  tbCase "xs" ["`tl b -> this f (f z a) b"
                              ,"`nil _ -> z"]]

-- srcFoldl = "fun this -> fun f -> fun z -> fun xs ->                 \
--            \ case xs of                                             \
--            \ { `nil junk -> z;                                      \
--            \   `hd a -> case xs of                                  \
--            \       {`tl b -> this f (f z a) b;                      \
--            \        `nil _ -> z}                                    \
--            \ }                                                      "

srcFoldr =
  tbScape ["this", "f", "z", "xs"] $
  tbCase "xs" [ tbScape ["`nil _"] "z"
              , tbScape ["`hd a"] $
                  tbCase "xs" ["`tl b -> f a (this f z b)"
                              ,"`nil _ -> z"]]

-- srcFoldr = "fun this -> fun f -> fun z -> fun xs ->                 \
--            \ case xs of                                             \
--            \ { `nil junk -> z;                                      \
--            \   `hd a -> case xs of                                  \
--            \       {`tl b -> f a (this f z b);                      \
--            \        `nil _ -> z}                                    \
--            \ }                                                      "

-- These forms use multipatterns to simplify their cases.

srcSum1Pats =
  tbScape ["this", "xs"] $
  tbCase "xs" ["`nil _ -> 0"
              ,"(`hd h & `tl t) -> h + (this t)"]

-- srcSum1Pats = "fun this -> fun xs ->                                \
--               \ case xs of {                                        \
--               \   `nil _ -> 0 ;                                     \
--               \   `hd h & `tl t -> h + (this t)                     \
--               \ }                                                   "

srcSum2Pats =
  tbScape ["this", "accum", "xs"] $
  tbCase "xs" ["`nil _ -> accum"
              ,"(`hd h & `tl t) -> this (h + accum) t"]

-- srcSum2Pats = "fun this -> fun accum -> fun xs ->                   \
--               \ case xs of {                                        \
--               \   `nil _ -> accum ;                                 \
--               \   `hd h & `tl t -> this (h + accum) t             \
--               \ }                                                   "

srcSum3Pats =
  tbScape ["this", "xs"] $
  tbCase "xs" ["(`nil _ & `acc accum) -> accum"
              ,"(`hd h & `tl t & `acc accum) -> this (t & `acc (h + accum))"]

-- srcSum3Pats = "fun this -> fun xs ->                                \
--               \ case xs of {                                        \
--               \   `nil _ & `acc accum -> accum ;                    \
--               \   `hd h & `tl t & `acc accum ->                     \
--               \     this (t & `acc (h + accum))                   \
--               \ }                                                   "

srcSum4Pats =
  tbDef "accum" "0" $
  tbScape ["this", "xs"] $
  tbCase "xs" [ tbScape ["`nil _"] "accum"
              , tbScape ["(`hd h & `tl t)"] $
                  tbAssign "accum" "accum + h" "this t"]

-- srcSum4Pats = "def accum = 0 in                                     \
--               \ fun this -> fun xs ->                               \
--               \   case xs of {                                      \
--               \     `nil _ -> accum ;                               \
--               \     `hd h & `tl t -> accum = accum + h in this t  \
--               \   }                                                 "

srcFoldlPats =
  tbScape ["this", "f", "z", "xs"] $
  tbCase "xs" ["`nil _ -> z"
              ,"(`hd h & `tl t) -> this f (f z h) t"]

-- srcFoldlPats = "fun this -> fun f -> fun z -> fun xs ->             \
--                \ case xs of {                                       \
--                \   `nil _ -> z ;                                    \
--                \   `hd h & `tl t -> this f (f z h) t                \
--                \ }                                                  "

srcFoldrPats =
  tbScape ["this", "f", "z", "xs"] $
  tbCase "xs" ["`nil _ -> z"
              ,"(`hd h & `tl t) -> f h (this f z t)"]

-- srcFoldrPats = "fun this -> fun f -> fun z -> fun xs ->             \
--                \ case xs of {                                       \
--                \   `nil _ -> z ;                                    \
--                \   `hd h & `tl t -> f h (this f z t)                \
--                \ }                                                  "

-- TODO: These forms use scapes to further simplify their cases.

testSum xs = map ($ V.pi $ sum xs)
  [ xEval $ srcMultiAppl
      [srcY, srcSum1, srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcSum2, "0", srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcSum3, "`acc 0 & " ++ srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcSum4, srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcFoldl, srcPlus, "0", srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcFoldr, srcPlus, "0", srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcSum1Pats, srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcSum2Pats, "0", srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcSum3Pats, "`acc 0 & " ++ srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcSum4Pats, srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcFoldlPats, srcPlus, "0", srcMakeList xs]
  , xEval $ srcMultiAppl
      [srcY, srcFoldrPats, srcPlus, "0", srcMakeList xs]
  ]
  where srcPlus = "x -> y -> x + y"

-- TODO: quickcheck that testsum works for all lists.

tests :: (?conf :: Cfg.Config) => Test
tests = TestLabel "List encoding tests" $ TestList $ concat
  [ testSum []
  , testSum [1]
  , testSum [1,2]
  , testSum [1,2,3]
  , testSum [1,2,3,4,5,6,7,8,9]
  ]