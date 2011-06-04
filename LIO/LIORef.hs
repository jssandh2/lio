-- |This module implements labeled IORefs.  The interface is analogous
-- to "Data.IORef", but the operations take place in the LIO monad.
-- Moreover, reading the LIORef calls taint, while writing it calls
-- wguard.
module LIO.LIORef (LIORef
                  , newLIORef, labelOfLIORef
                  , readLIORef, writeLIORef, atomicModifyLIORef
                  ) where

import LIO.TCB
import Data.IORef
import Control.Monad (unless)


data LIORef l a = LIORefTCB l (IORef a)

wguardNoTaint l = do
  l' <- currentLabel 
  unless (l' `leq` l) $ throwIO LerrHigh


newLIORef :: (Label l) => l -> a -> LIO l s (LIORef l a)
newLIORef l a = do
  wguardNoTaint l
  ior <- ioTCB $ newIORef a
  return $ LIORefTCB l ior

labelOfLIORef :: (Label l) => LIORef l a -> l
labelOfLIORef (LIORefTCB l _) = l

readLIORef :: (Label l) => LIORef l a -> LIO l s a
readLIORef (LIORefTCB l r) = do
  taint l
  val <- ioTCB $ readIORef r
  return val

writeLIORef :: (Label l) => LIORef l a -> a -> LIO l s ()
writeLIORef (LIORefTCB l r) a = do
  wguardNoTaint l
  ioTCB $ writeIORef r a

atomicModifyLIORef :: (Label l) =>
                      LIORef l a -> (a -> (a, b)) -> LIO l s b
atomicModifyLIORef (LIORefTCB l r) f = do
  wguardNoTaint l
  ioTCB $ atomicModifyIORef r f

