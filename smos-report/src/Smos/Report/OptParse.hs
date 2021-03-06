{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module Smos.Report.OptParse where

import Control.Arrow
import Control.Monad
import Data.Aeson as JSON (eitherDecodeFileStrict)
import Data.Aeson (FromJSON)
import Data.Maybe
import qualified Data.Text as T
import Data.Yaml as Yaml (decodeFileEither, prettyPrintParseException)
import Options.Applicative
import Path
import Path.IO
import Smos.Report.Config
import Smos.Report.OptParse.Types
import qualified System.Environment as System
import System.Exit
import YamlParse.Applicative hiding (Parser)

combineToConfig ::
  SmosReportConfig -> Flags -> Environment -> Maybe Configuration -> IO SmosReportConfig
combineToConfig src Flags {..} Environment {..} mc = do
  wfs <-
    case msum [flagWorkflowDir, envWorkflowDir, mc >>= (fmap T.unpack . confWorkflowDir)] of
      Nothing -> pure $ smosReportConfigWorkflowFileSpec src
      Just wd -> do
        ad <- resolveDir' wd
        pure $ DirAbsolute ad
  afs <-
    case msum [flagArchiveDir, envArchiveDir, mc >>= (fmap T.unpack . confArchiveDir)] of
      Nothing -> pure $ smosReportConfigArchiveFileSpec src
      Just wd -> do
        ad <- resolveDir' wd
        pure $ ArchiveAbsolute ad
  pfs <-
    case msum [flagProjectsDir, envProjectsDir, mc >>= (fmap T.unpack . confProjectsDir)] of
      Nothing -> pure $ smosReportConfigProjectsFileSpec src
      Just wd -> do
        ad <- resolveDir' wd
        pure $ ProjectsAbsolute ad
  apfs <-
    case msum
      [ flagArchivedProjectsDir,
        envArchivedProjectsDir,
        mc >>= (fmap T.unpack . confArchivedProjectsDir)
      ] of
      Nothing -> pure $ smosReportConfigArchivedProjectsFileSpec src
      Just wd -> do
        ad <- resolveDir' wd
        pure $ ArchivedProjectsAbsolute ad
  pure $
    SmosReportConfig
      { smosReportConfigWorkflowFileSpec = wfs,
        smosReportConfigArchiveFileSpec = afs,
        smosReportConfigProjectsFileSpec = pfs,
        smosReportConfigArchivedProjectsFileSpec = apfs,
        smosReportConfigWorkBaseFilter =
          (mc >>= confWorkBaseFilter) <|> smosReportConfigWorkBaseFilter src,
        smosReportConfigContexts = fromMaybe (smosReportConfigContexts src) (mc >>= confContexts)
      }

parseFlags :: Parser Flags
parseFlags =
  Flags <$> parseConfigFileFlag <*> parseWorkflowDirFlag <*> parseArchiveDirFlag
    <*> parseProjectsDirFlag
    <*> parseArchivedProjectsDirFlag

parseConfigFileFlag :: Parser (Maybe FilePath)
parseConfigFileFlag =
  option
    (Just <$> str)
    (mconcat [metavar "FILEPATH", help "The config file to use", long "config-file", value Nothing])

parseWorkflowDirFlag :: Parser (Maybe FilePath)
parseWorkflowDirFlag =
  option
    (Just <$> str)
    ( mconcat
        [ metavar "FILEPATH",
          help "The workflow directory to use",
          long "workflow-dir",
          value Nothing
        ]
    )

parseArchiveDirFlag :: Parser (Maybe FilePath)
parseArchiveDirFlag =
  option
    (Just <$> str)
    ( mconcat
        [metavar "FILEPATH", help "The archive directory to use", long "archive-dir", value Nothing]
    )

parseProjectsDirFlag :: Parser (Maybe FilePath)
parseProjectsDirFlag =
  option
    (Just <$> str)
    ( mconcat
        [ metavar "FILEPATH",
          help "The projects directory to use",
          long "projects-dir",
          value Nothing
        ]
    )

parseArchivedProjectsDirFlag :: Parser (Maybe FilePath)
parseArchivedProjectsDirFlag =
  option
    (Just <$> str)
    ( mconcat
        [ metavar "FILEPATH",
          help "The archived projects directory to use",
          long "archived-projects-dir",
          value Nothing
        ]
    )

getEnvironment :: IO Environment
getEnvironment = do
  env <- System.getEnvironment
  let getSmosEnv :: String -> Maybe String
      getSmosEnv key = ("SMOS_" ++ key) `lookup` env
  pure
    Environment
      { envConfigFile = msum $ map getSmosEnv ["CONFIGURATION_FILE", "CONFIG_FILE", "CONFIG"],
        envWorkflowDir =
          msum $ map getSmosEnv ["WORKFLOW_DIRECTORY", "WORKFLOW_DIR", "WORKFLOW_DIR"],
        envArchiveDir = msum $ map getSmosEnv ["ARCHIVE_DIRECTORY", "ARCHIVE_DIR", "ARCHIVE_DIR"],
        envProjectsDir =
          msum $ map getSmosEnv ["PROJECTS_DIRECTORY", "PROJECTS_DIR", "PROJECTS_DIR"],
        envArchivedProjectsDir =
          msum $
            map
              getSmosEnv
              ["ARCHIVED_PROJECTS_DIRECTORY", "ARCHIVED_PROJECTS_DIR", "ARCHIVED_PROJECTS_DIR"]
      }

defaultConfigFiles :: IO [Path Abs File]
defaultConfigFiles = do
  home <- getHomeDir
  homeConfigDir <- resolveDir home ".smos"
  xdgConfigDir <- getXdgDir XdgConfig (Just [reldir|smos|])
  let inDirs = do
        d <- [xdgConfigDir, homeConfigDir]
        pure $ d </> [relfile|config|]
  plainFile <- resolveFile home ".smos"
  let files = inDirs ++ [plainFile]
  pure $ do
    file <- files
    ext <- [".yaml", ".json"]
    addFileExtension ext file

parseYamlConfig :: FromJSON a => Path Abs File -> IO (Either String a)
parseYamlConfig configFile =
  fmap (left prettyPrintParseException) $ decodeFileEither $ fromAbsFile configFile

parseJSONConfig :: FromJSON a => Path Abs File -> IO (Either String a)
parseJSONConfig configFile = JSON.eitherDecodeFileStrict $ fromAbsFile configFile

getConfiguration :: (FromJSON a, YamlSchema a) => Flags -> Environment -> IO (Maybe a)
getConfiguration Flags {..} Environment {..} = do
  mConfigFile <-
    case msum [flagConfigFile, envConfigFile] of
      Nothing -> do
        files <- defaultConfigFiles
        let go [] = pure Nothing
            go (f : fs) = do
              e <- doesFileExist f
              if e
                then pure $ Just f
                else go fs
        go files
      Just fp -> Just <$> resolveFile' fp
  forM mConfigFile $ \configFile -> do
    errOrConfig <-
      case fileExtension configFile of
        ".json" -> parseJSONConfig configFile
        -- As Yaml
        ".yaml" -> parseYamlConfig configFile
        _ -> parseYamlConfig configFile
    case errOrConfig of
      Left err -> die $ unlines [err, "Config format reference:", T.unpack $ prettySchema $ explainParser $ yamlSchema @Configuration]
      Right conf -> pure conf
