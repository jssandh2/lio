
module Main (module LIO.TCB, module Main
            , evalHS) where

import LIO.TCB
import LIO.HiStar
import Control.Exception

--
-- Crap
--

lgetLine = ioTCB getLine
lputStr x = ioTCB $ putStr x
lputStrLn x = ioTCB $ putStrLn x

us = HSC 99
ul = lupdate lpure us L3

vs = HSC 104
vl = lupdate lpure vs L3

three, four :: Lref HSLabel Int
three = lrefTCB ul 3
four = lrefTCB vl 4

privs = HSPrivs [us, vs]

etest :: HS Int
etest = do
  a <- openL four
  -- rethrowTCB $ throw $ AssertionFailed "etest"
  rethrowTCB $ return $ (a `div` 0)

addem = do
  a <- openL three
  b <- openL four
  return $ a + b

a2 = do
  sum <- closeL addem
  lputStrLn $ showTCB sum
  

crap = do
  a <- openL three
  (p1, l1) <- newcat L2
  five <- openL $ lrefTCB l1 5
  -- let five' = unlabel p1 (label l1 5)
  lputStrLn $ show five

foo = do
  x <- three
  y <- four
  return $ x + y

getnum :: HS Int
getnum = do
  lputStr "Enter a number: "
  s <- lgetLine
  return (read s :: Int)

mft ~(a, b) = do
  a' <- getnum 
  return (a', a+1)

main = return ()
