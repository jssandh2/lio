module LambdaReview where

import Control.Monad
import Control.Monad.State
import Data.Maybe
import Data.List
import Data.Monoid

import LIO.TCB
import LIO.LIORef
import LIO.MonadLIO
import LIO.DCLabel
import LIO.DCLabel.NanoEDSL

type DCLabeled = LrefD DCLabel
type DCRef     = LIORef DCLabel

-- ^ Clss to with sideffectful show
class DCShowTCB s where
  dcShowTCB :: s -> DC String

dcPutStrLnTCB :: String -> DC ()
dcPutStrLnTCB = ioTCB . putStrLn

type Name = String
type Password = String
type Content = String
type Reviews = String

type Id     = Int
data Paper  = Paper  Content
data Review = Review (DCLabeled Content)

data User = User { name :: Name
                 , password :: Password
                 , conflicts :: [Id] }

instance Eq User where
  u1 == u2 = name u1 == name u2

instance DCShowTCB User where
  dcShowTCB u = do
    return $  "Name: " ++ (name u) ++ "\n"
           ++ "Password: " ++ (password u) ++ "\n"
           ++ "Conflicts: " ++ (show . conflicts $ u)

data ReviewEnt =  ReviewEnt { paperId :: Id
                            , paper   :: DCRef Paper
                            , review  :: DCRef Review }

instance Eq ReviewEnt where
  r1 == r2 = paperId r1 == paperId r2

instance DCShowTCB ReviewEnt where
  dcShowTCB r = do
    (Paper pap)  <- readLIORefTCB (paper r)
    (Review rev) <- readLIORefTCB (review r)
    return $  "ID:" ++ (show . paperId $ r)
           ++ "\nPaper:" ++ pap
           ++ "\nReviews:" ++ (showTCB $ rev)


-- State related
data ReviewState = ReviewState { users :: [User]
                               , reviewEntries :: [ReviewEnt]
                               , curUser :: Maybe Name }

emptyReviewState :: ReviewState
emptyReviewState = ReviewState [] [] Nothing

type ReviewDC = StateT ReviewState DC 

runReviewDC :: ReviewDC a -> ReviewState -> DC (a, ReviewState)
runReviewDC m s = runStateT m s

evalReviewDC :: ReviewDC a -> IO (a, DCLabel)
evalReviewDC m = evalDC $ do
  (a, s') <- runReviewDC m emptyReviewState
  return a
--

-- ^ Get all users
getUsers :: ReviewDC [User]
getUsers = get >>= return . users

-- ^ Get all review entries
getReviews :: ReviewDC [ReviewEnt]
getReviews = get >>= return . reviewEntries

-- ^ Get priviliges
getCurUserName :: ReviewDC (Maybe Name)
getCurUserName = get >>= return . curUser

getCurUser :: ReviewDC (Maybe User)
getCurUser = do
  n <- getCurUserName
  maybe (return Nothing) findUser n

-- ^ Get priviliges
getPrivs :: ReviewDC DCPrivs
getPrivs = do 
  u <- getCurUser
  return $ maybe mempty (genPrivTCB . name) u

-- ^ Write new users
putUsers :: [User] -> ReviewDC ()
putUsers us = do
  rs <- getReviews
  u <- getCurUserName
  put $ ReviewState us rs u

-- ^ Write new reviews
putReviews :: [ReviewEnt] -> ReviewDC ()
putReviews rs = do
  us <- getUsers
  u <- getCurUserName
  put $ ReviewState us rs u

-- ^ Write new privs
putCurUserName :: Name -> ReviewDC ()
putCurUserName u = do
  us <- getUsers
  rs <- getReviews
  put $ ReviewState us rs (Just u)

-- ^ Find review entry by id
findReview :: Id -> ReviewDC (Maybe ReviewEnt)
findReview pId = do
  reviews <- getReviews
  return $ find (\e -> paperId e == pId) reviews

-- ^ Find user by name
findUser :: Name -> ReviewDC (Maybe User)
findUser n = do
  users <- getUsers
  return $ find (\u -> name u == n) users 

-- ^ Add new (fresh) user
addUser :: Name -> Password -> ReviewDC ()
addUser n p = do
  u <- findUser n
  unless (isJust u) $ do
    let newUser = User { name = n
                       , password = p
                       , conflicts = [] }
    us <- getUsers
    putUsers (newUser:us)

-- ^ Add conflicting paper to user
addConflict :: Name -> Id -> ReviewDC ()
addConflict n i = do
  usr <- findUser n
  pap <- findReview i
  case (usr, pap) of
    (Just u, Just _) -> do
      let u' = u { conflicts = i : (conflicts u)}
      usrs <- getUsers
      putUsers $ u' : (filter (/= u) usrs)
      return ()
      
    _ -> return ()

-- ^ Print users
printUsersTCB :: ReviewDC ()
printUsersTCB = do
 users <- getUsers
 mapM (liftLIO . dcShowTCB) users >>=
   liftLIO . dcPutStrLnTCB . (intercalate "\n--\n")

-- ^ Print papers and reviews
printReviewsTCB :: ReviewDC ()
printReviewsTCB = do
 reviews <- getReviews
 mapM (liftLIO . dcShowTCB) reviews >>=
   liftLIO . dcPutStrLnTCB . (intercalate "\n--\n")

-- | Generate privilege from a string
genPrivTCB :: String -> DCPrivs
genPrivTCB = mintTCB . Principal


-- ^ Create new paper given id and content
newReviewEnt :: Id -> Content -> ReviewDC ReviewEnt
newReviewEnt pId content = do
  let p1 = "Paper" ++ (show pId)
      r1 = "Review" ++ (show pId)
      emptyLabel = exprToDCLabel r1 (("Alice" .\/. "Bob") ./\. r1)
      pLabel = exprToDCLabel NoPrincipal p1
      rLabel = exprToDCLabel r1 r1
      privs = mconcat $ map genPrivTCB [p1, r1, "Alice", "Bob"]
  liftLIO $ do
    lEmptyRev  <- lrefPD privs emptyLabel "EMPTY REVIEW" -- TODO: CHANGE!!
    rPaper  <- newLIORefP privs pLabel (Paper content)
    rReview <- newLIORefP privs rLabel (Review lEmptyRev)
    return $ ReviewEnt pId rPaper rReview

-- ^ Adda new paper to be reviewed
addPaper :: Content -> ReviewDC ()
addPaper content = do
  reviews <- getReviews
  let pId = 1 + (length reviews)
  ent <- newReviewEnt pId content
  putReviews (ent:reviews)

-- ^ Given a paper number return the paper
readPaper :: Id -> ReviewDC (Either String Content)
readPaper pId = do
  mRev <- findReview pId 
  case mRev of 
    Nothing -> return $ Left "Invalid Id"
    Just rev -> do p <- doReadPaper rev
                   return $ Right p
   where doReadPaper rev = liftLIO $ do
             (Paper lPaper) <- readLIORef (paper rev)
             return lPaper

-- ^ Given a paper number return the review
readReview :: Id -> ReviewDC (Either String ())
readReview pId = do
  mRev <- findReview pId 
  case mRev of 
    Nothing -> return $ Left "Invalid Id"
    Just rev -> do mu <- getCurUser
                   case mu of
                    Nothing -> return $ Left "Must login first"
                    Just u -> do
                     l <- getOutputChLbl
                     r <- doReadReview l rev
                     return $ Right r
   where doReadReview l rev = liftLIO $ do
             (Review lReview) <- readLIORef (review rev)
             rev <- openRD lReview
             dcPutStrLn l rev

getOutputChLbl :: ReviewDC (DCLabel) 
getOutputChLbl = do
  mu <- getCurUser
  case mu of
    Nothing -> return $ DCLabel dcsEmpty dcsEmpty
    Just u -> do
      let cs = conflicts u
      rs <- getReviews >>= return . map paperId
      let ok = map id2c (rs \\ cs)
          conf = map id2c' cs
          s = dcsFromList $ ok ++ conf
      return $ DCLabel s dcsEmpty

        where id2c  i = dcSingleton Secrecy . Principal $ "Review"++(show i)
              id2c' i = exprToDCat Secrecy (("Review"++(show i)) .\/. "CONFLICT")
          



dcPutStrLn :: DCLabel -> Content -> DC ()
dcPutStrLn l cont = do
  lc <- currentLabel
  --dcPutStrLnTCB (show $ dclS lc)
  if lc `leq` l
    then dcPutStrLnTCB cont
    else dcPutStrLnTCB "Conflict of interest!"


appendToReview :: Id -> Content -> ReviewDC (Either String ())
appendToReview pId content = do
  mRev <- findReview pId 
  case mRev of 
    Nothing -> return $ Left "Invalid Id"
    Just rev -> do privs <- getPrivs
                   doWriteReview privs rev content
                   return $ Right ()
   where doWriteReview privs rev content = liftLIO $ do
             (Review lReview) <- readLIORef (review rev)
             rs <- openRD lReview
             dcPutStrLnTCB (showTCB lReview)
             lReview' <- lrefPD privs (labelOfRD lReview) (rs++content)
             writeLIORef (review rev) (Review lReview')

main = evalReviewDC $ do
  addUser "Alice" "password"
  addUser "Bob" "pass"
  addUser "Clarice" "bss"
  addPaper "Paper content"
  addPaper "Another paper content"
  addConflict "Alice" 1
--  liftLIO $ setLabelTCB aliceLabel
  liftLIO . setLabelTCB $ exprToDCLabel NoPrincipal ("Review1" ./\. "Review2")
  putCurUserName "Bob"
--  liftLIO . setClearanceTCB $ exprToDCLabel (u {- ./\. "Review1" -}) NoPrincipal
  --lc <- liftLIO $ currentLabel
  --liftLIO . dcPutStrLnTCB $ "CurLabel = " ++ (show lc)
  {-
  appendToReview 2 "bad"
  appendToReview 2 "why"
  appendToReview 2 "nono"
  readPaper 1 >>= liftLIO . dcPutStrLnTCB . show
  readPaper 2 >>= liftLIO . dcPutStrLnTCB . show
  -}
  readReview 1
  printUsersTCB
  printReviewsTCB



-- Add paper
-- Add reviewer: can read any paper or non-conflicting review 
-- Add conflict: should prevent a reviewer from reading the reviews
-- Remove conflict: should now allow the reviewer to read reviews
-- Assign reviewer: assing a reviewer to a paper
-- Login
