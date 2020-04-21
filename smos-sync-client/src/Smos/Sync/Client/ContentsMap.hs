{-# LANGUAGE DeriveGeneric #-}

-- |
--
-- Import this module qualified
module Smos.Sync.Client.ContentsMap
  ( ContentsMap (..),
    empty,
    singleton,
    insert,
    union,
    unions,
  )
where

import Control.DeepSeq
import Control.Monad
import Data.ByteString (ByteString)
import Data.Map (Map)
import qualified Data.Map as M
import Data.Validity
import Data.Validity.ByteString ()
import Data.Validity.Containers ()
import Data.Validity.Path ()
import GHC.Generics (Generic)
import Path
import Smos.Sync.Client.DirTree as DT

type ContentsMap = DirForest ByteString

empty :: ContentsMap
empty = emptyDirForest

singleton :: Path Rel File -> ByteString -> ContentsMap
singleton = singletonDirForest

insert :: Path Rel File -> ByteString -> ContentsMap -> Maybe ContentsMap
insert rp cs cm = case insertDirForest rp cs cm of
  Left _ -> Nothing
  Right r -> Just r

union :: ContentsMap -> ContentsMap -> Maybe ContentsMap
union cm1 cm2 = case unionDirForest cm1 cm2 of
  Left _ -> Nothing
  Right r -> Just r

unions :: [ContentsMap] -> Maybe ContentsMap
unions cms = case unionsDirForest cms of
  Left _ -> Nothing
  Right r -> Just r
