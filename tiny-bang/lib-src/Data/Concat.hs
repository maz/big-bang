{-# LANGUAGE TemplateHaskell, MultiParamTypeClasses, FlexibleInstances #-}

module Data.Concat
( Concatenatable(..)
, concatenateM
, (+^+)
) where

import GHC.Exts (maxTupleSize)

import Control.Applicative ((<$>))
import Language.Haskell.TH

import Utils.TemplateHaskell

class Concatenatable a b c where
  -- |A function to concatenate two values.
  concatenate :: a -> b -> c
  -- |An infix alias for @concatenate@.
  (+++) :: a -> b -> c
  (+++) = concatenate
  infixl 3 +++
  
-- |A function to concatenate two monadic values.  Effects from the first
--  argument are applied first.
concatenateM :: (Concatenatable a b c, Monad m) => m a -> m b -> m c
concatenateM aM bM = do
  a <- aM
  b <- bM
  return $ a +++ b
  
-- |An infix alias for @concatenateM@.
(+^+) :: (Concatenatable a b c, Monad m) => m a -> m b -> m c
(+^+) = concatenateM
infixl 3 +^+
  
instance Concatenatable [a] [a] [a] where
  concatenate = (++)

-- Define instances of concatenation
$(
  let tupleInstanceSize = 15{-maxTupleSize-} in
  let tupleInstance :: Int -> Int -> Q [Dec]
      tupleInstance n m =
        let namesA = mkNames "a" n
            namesB = mkNames "b" m
            typeA = mkTupleType namesA
            typeB = mkTupleType namesB
            typeC = mkTupleType $ namesA ++ namesB
            nmA = mkName "a"
            nmB = mkName "b"
            expr = 
              LetE (map (\(nm,nms) -> ValD (TupP $ map VarP nms)
                                  (NormalB $ VarE nm) [])
                      [(nmA,namesA),(nmB,namesB)]) $
                TupE $ map VarE $ namesA ++ namesB
            defn = FunD (mkName "concatenate") [Clause [VarP nmA, VarP nmB]
                      (NormalB expr) []]
            inst = InstanceD []
                      (foldl AppT (ConT $ mkName "Concatenatable")
                        [typeA, typeB, typeC])
                      [defn]
        in
        return [inst]
        where
          mkTupleType names =
            foldl AppT (TupleT $ length names) (map VarT names)
  in
  concat <$> sequence
    [ tupleInstance n m
    | n <- [0..tupleInstanceSize]
    , m <- [0..tupleInstanceSize]
    , n+m <= maxTupleSize ]
 )

