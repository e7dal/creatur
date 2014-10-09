------------------------------------------------------------------------
-- |
-- Module      :  ALife.Creatur.Task
-- Copyright   :  (c) Amy de Buitléir 2012-2014
-- License     :  BSD-style
-- Maintainer  :  amy@nualeargais.ie
-- Stability   :  experimental
-- Portability :  portable
--
-- Provides tasks that you can use with a daemon. These tasks handle
-- reading and writing agents, and various other housekeeping chores,
-- which reduces the amount of code you need to write. 
--
-- It’s also easy to write your own tasks, using these as a guide.)
--
------------------------------------------------------------------------
{-# LANGUAGE TypeFamilies, FlexibleContexts #-}

module ALife.Creatur.Task
 (
    AgentProgram,
    AgentsProgram,
    withAgent,
    withAgents,
    runNoninteractingAgents,
    runInteractingAgents,
    simpleDaemon,
    startupHandler,
    shutdownHandler,
    exceptionHandler,
    nothing
 ) where

import ALife.Creatur.Daemon (Daemon(..))
import qualified ALife.Creatur.Daemon as D
import ALife.Creatur.Universe (Universe, Agent, AgentProgram,
  AgentsProgram, writeToLog, lineup, refreshLineup, markDone, endOfRound,
  withAgent, withAgents, incTime, popSize)
import Control.Conditional (whenM)
import Control.Exception (SomeException)
import Control.Monad (when)
import Control.Monad.State (StateT, execStateT, evalStateT)
import Control.Monad.Trans.Class (lift)
import Data.Serialize (Serialize)

simpleDaemon :: Universe u => Daemon u
simpleDaemon = Daemon
  {
    onStartup = startupHandler,
    onShutdown = shutdownHandler,
    onException = exceptionHandler,
    task = undefined,
    username = "",
    sleepTime = 100
  }

startupHandler :: Universe u => u -> IO u
startupHandler = execStateT (writeToLog $ "Starting")

shutdownHandler :: Universe u => u -> IO ()
shutdownHandler u = evalStateT (writeToLog "Shutdown requested") u

exceptionHandler :: Universe u => u -> SomeException -> IO u
exceptionHandler u x = execStateT (writeToLog ("WARNING: " ++ show x)) u

runNoninteractingAgents
  :: (Universe u, Serialize (Agent u))
    => AgentProgram u -> (Int, Int) -> StateT u IO () -> StateT u IO ()
      -> StateT u IO ()
runNoninteractingAgents agentProgram popRange startRoundProgram
    endRoundProgram = do
  atStartOfRound startRoundProgram
  as <- lineup
  when (not . null $ as) $ do
    let a = head as
    markDone a
    -- do that first in case the next line triggers an exception
    withAgent agentProgram a
    atEndOfRound endRoundProgram
    checkPopSize popRange

--   The input parameter is a list of agents. The first agent in the
--   list is the agent whose turn it is to use the CPU. The rest of
--   the list contains agents it could interact with. For example, if
--   agents reproduce sexually, the program might check if the first
--   agent in the list is female, and the second one is male, and if so,
--   mate them to produce offspring. The input list is generated in a
--   way that guarantees that every possible sequence of agents has an
--   equal chance of occurring.

runInteractingAgents
  :: (Universe u, Serialize (Agent u))
    => AgentsProgram u -> (Int, Int) -> StateT u IO () -> StateT u IO ()
      -> StateT u IO ()
runInteractingAgents agentsProgram popRange startRoundProgram
    endRoundProgram = do
  atStartOfRound startRoundProgram
  as <- lineup
  markDone (head as)
  -- do that first in case the next line triggers an exception
  withAgents agentsProgram as
  atEndOfRound endRoundProgram
  checkPopSize popRange

checkPopSize :: Universe u => (Int, Int) -> StateT u IO ()
checkPopSize (minAgents, maxAgents) = do
  n <- popSize
  writeToLog $ "Pop. size=" ++ show n
  when (n < minAgents) $ requestShutdown "population too small"
  when (n > maxAgents) $ requestShutdown "population too big"

requestShutdown :: Universe u => String -> StateT u IO ()
requestShutdown s = do
  writeToLog $ "Requesting shutdown: " ++ s
  lift D.requestShutdown

atStartOfRound :: Universe u => StateT u IO () -> StateT u IO ()
atStartOfRound program = do
  whenM endOfRound $ do
    refreshLineup
    incTime
    writeToLog "Beginning of round"
    program

atEndOfRound :: Universe u => StateT u IO () -> StateT u IO ()
atEndOfRound program = do
  whenM endOfRound $ do
    writeToLog "End of round"
    program

nothing :: StateT u IO ()
nothing = return ()

-- Note: There's no reason for the checklist type to be a parameter of
-- the Universe type. Users don't interact directly with it, so they
-- won't have any reason to want to use a different checklist
-- implementation.
