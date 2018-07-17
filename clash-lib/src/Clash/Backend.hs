{-|
  Copyright  :  (C) 2015-2016, University of Twente,
                    2017     , Myrtle Software Ltd, Google Inc.
  License    :  BSD2 (see the file LICENSE)
  Maintainer :  Christiaan Baaij <christiaan.baaij@gmail.com>
-}

{-# LANGUAGE OverloadedStrings #-}

module Clash.Backend where

import Data.HashSet                         (HashSet)
import Data.Maybe                           (fromMaybe)
import Data.Semigroup.Monad                 (Mon)
import qualified Data.Text.Lazy             as T
import Data.Text.Lazy                       (Text)
import Control.Monad.State                  (State)
import Data.Text.Prettyprint.Doc.Extra      (Doc)

import SrcLoc (SrcSpan)

import Clash.Netlist.Id
import {-# SOURCE #-} Clash.Netlist.Types
import Clash.Netlist.BlackBox.Types

import Clash.Annotations.Primitive          (HDL)

type ModName = String

-- | Is a type used for internal or external use
data Usage
  = Internal
  -- ^ Internal use
  | External Text
  -- ^ External use, field indicates the library name

class Backend state where
  -- | Initial state for state monad
  initBackend :: Int -> HdlSyn -> state

  -- | What HDL is the backend generating
  hdlKind :: state -> HDL

  -- | Location for the primitive definitions
  primDirs :: state -> IO [FilePath]

  -- | Name of backend, used for directory to put output files in. Should be
  -- | constant function / ignore argument.
  name :: state -> String

  -- | File extension for target langauge
  extension :: state -> String

  -- | Get the set of types out of state
  extractTypes     :: state -> HashSet HWType

  -- | Generate HDL for a Netlist component
  genHDL           :: String -> SrcSpan -> Component -> Mon (State state) ((String, Doc),[(String,Doc)])
  -- | Generate a HDL package containing type definitions for the given HWTypes
  mkTyPackage      :: String -> [HWType] -> Mon (State state) [(String, Doc)]
  -- | Convert a Netlist HWType to a target HDL type
  hdlType          :: Usage -> HWType -> Mon (State state) Doc
  -- | Convert a Netlist HWType to an HDL error value for that type
  hdlTypeErrValue  :: HWType       -> Mon (State state) Doc
  -- | Convert a Netlist HWType to the root of a target HDL type
  hdlTypeMark      :: HWType       -> Mon (State state) Doc
  -- | Create a record selector
  hdlRecSel        :: HWType -> Int -> Mon (State state) Doc
  -- | Create a signal declaration from an identifier (Text) and Netlist HWType
  hdlSig           :: Text -> HWType -> Mon (State state) Doc
  -- | Create a generative block statement marker
  genStmt          :: Bool -> State state Doc
  -- | Turn a Netlist Declaration to a HDL concurrent block
  inst             :: Declaration  -> Mon (State state) (Maybe Doc)
  -- | Turn a Netlist expression into a HDL expression
  expr             :: Bool -> Expr -> Mon (State state) Doc
  -- | Bit-width of Int/Word/Integer
  iwWidth          :: State state Int
  -- | Convert to a bit-vector
  toBV             :: HWType -> Text -> Mon (State state) Doc
  -- | Convert from a bit-vector
  fromBV           :: HWType -> Text -> Mon (State state) Doc
  -- | Synthesis tool we're generating HDL for
  hdlSyn           :: State state HdlSyn
  -- | mkIdentifier
  mkIdentifier     :: State state (IdType -> Identifier -> Identifier)
  -- | mkIdentifier
  extendIdentifier :: State state (IdType -> Identifier -> Identifier -> Identifier)
  -- | setModName
  setModName       :: ModName -> state -> state
  -- | setSrcSpan
  setSrcSpan       :: SrcSpan -> State state ()
  -- | getSrcSpan
  getSrcSpan       :: State state SrcSpan
  -- | Block of declarations
  blockDecl        :: Text -> [Declaration] -> Mon (State state) Doc
  -- | unextend/unescape identifier
  unextend         :: State state (Identifier -> Identifier)
  addIncludes      :: [(String, Doc)] -> State state ()
  addLibraries     :: [Text] -> State state ()
  addImports       :: [Text] -> State state ()

-- | Replace a normal HDL template placeholder with an unescaped/unextended
-- template placeholder.
--
-- Needed when the the place-holder is filled with an escaped/extended identifier
-- inside an escaped/extended identifier and we want to strip the escape
-- /extension markers. Otherwise we end up with illegal identifiers.
escapeTemplate :: Identifier -> Identifier
escapeTemplate "~RESULT" = "~ERESULT"
escapeTemplate t = fromMaybe t $ do
  t1 <- T.stripPrefix "~ARG[" t
  n  <- T.stripSuffix "]" t1
  pure (T.concat ["~EARG[",n,"]"])
