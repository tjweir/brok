{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Brok
    ( brok
    ) where

import ClassyPrelude

import Data.FileEmbed (embedFile)
import Data.Text.IO   (hPutStrLn)
import System.Exit    (exitFailure, exitSuccess)

import           Brok.IO.CLI       (header, replace)
import           Brok.IO.DB        (getCached, setCached)
import           Brok.IO.Document  (readContent)
import           Brok.IO.Http      (check)
import           Brok.IO.Output    (output)
import           Brok.Options      (parse)
import           Brok.Parser.Links (links)
import           Brok.Types.App    (App)
import qualified Brok.Types.Config as C (files, ignore, interval, onlyFailures)
import           Brok.Types.Link   (getURL, isSuccess)
import           Brok.Types.Next   (Next (..))
import           Brok.Types.Result (cachedLinks, ignoredLinks, justLinks, linkIOMap, parseLinks,
                                    pathToResult)

go :: App ()
go = do
    config <- ask
    -- read files
    content <- traverse (readContent . pathToResult) (C.files config)
    -- find links in each file
    let parsed = parseLinks links <$> content
    -- check cached successes
    cached <- getCached
    let uncached = cachedLinks cached . ignoredLinks (C.ignore config) <$> parsed
    -- check links in each file
    header "Checking URLs"
    putStrLn ""
    checked <- traverse (linkIOMap (check (C.interval config))) uncached
    replace "Fetching complete"
    -- display results
    putStrLn ""
    header "Results"
    anyErrors <- output (C.onlyFailures config) checked
    -- cache successes
    setCached $ getURL <$> filter isSuccess (concat (justLinks <$> checked))
    -- exit with appropriate status code
    lift $
        if anyErrors
            then void exitFailure
            else void exitSuccess

showHelp :: IO ()
showHelp = putStr $ decodeUtf8 $(embedFile "template/usage.txt")

-- entry point
brok :: IO ()
brok = do
    config <- parse <$> getArgs
    case config of
        Right (Continue cnf) -> runReaderT go cnf
        Right Help -> showHelp
        Left _ -> do
            hPutStrLn stderr "Invalid format"
            showHelp
            void exitFailure
