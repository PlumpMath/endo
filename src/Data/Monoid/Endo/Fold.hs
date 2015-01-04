{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TypeFamilies #-}

#if MIN_VERSION_transformers(0,4,0)
-- ExceptT was introduced in transformers == 0.4.0.0 and it deprecated ErrorT.
-- That is also the reason why ErrorT instance is not provided.
#define HAVE_EXCEPTT
#endif

-- |
-- Module:       $HEADER$
-- Description:  Generic folding for various endomorphism representations.
-- Copyright:    (c) 2014, 2015 Peter Trsko
-- License:      BSD3
--
-- Maintainer:   peter.trsko@gmail.com
-- Stability:    experimental
-- Portability:  CPP, DeriveDataTypeable, DeriveGeneric, FlexibleInstances,
--               NoImplicitPrelude, TypeFamilies
--
-- Generic folding for various endomorphism representations.
module Data.Monoid.Endo.Fold
    (
    -- * Usage Example
    -- $usageExample

    -- * API
      foldEndo
    , dualFoldEndo
    , FoldEndoArgs(..)
    , AnEndo(..)

    -- ** Type Wrappers
    , WrappedFoldable(..)

    -- * Utility Functions
    , (&$)
    )
  where

import Control.Applicative (Applicative(pure))
import Control.Monad (Monad(return))
import Data.Data (Data)
import Data.Either (Either(Right))
import Data.Foldable (Foldable(foldMap))
import Data.Function ((.), id)
#ifndef APPLICATIVE_MONAD
import Data.Functor (Functor)
#endif
import Data.Functor.Identity (Identity(Identity))
import Data.Maybe (Maybe(Just, Nothing))
import Data.Monoid (Dual(Dual), Endo(Endo), Monoid(mempty, mconcat), (<>))
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import System.IO (IO)
import Text.Read (Read)
import Text.Show (Show)

#if HAVE_EXCEPTT
import Control.Monad.Trans.Except (ExceptT)
#endif
import Control.Monad.Trans.Identity (IdentityT)
import Control.Monad.Trans.List (ListT)
import Control.Monad.Trans.Maybe (MaybeT)
import Control.Monad.Trans.Reader (ReaderT)
import Control.Monad.Trans.RWS (RWST)
import qualified Control.Monad.Trans.RWS.Strict as Strict (RWST)
import Control.Monad.Trans.State (StateT)
import qualified Control.Monad.Trans.State.Strict as Strict (StateT)
import Control.Monad.Trans.Writer (WriterT)
import qualified Control.Monad.Trans.Writer.Strict as Strict (WriterT)
import Data.Functor.Compose (Compose)
import Data.Functor.Product (Product)
import Data.Functor.Reverse (Reverse)


-- | Fold all variously represented endomorphisms in to one endomorphism.
--
-- Order in which endomorphisms are folded is preserved:
--
-- >>> foldEndo (Endo (1:)) [(2:), (3:)] `appEndo` []
-- [1,2,3]
--
-- For numbers it would look like:
--
-- >>> foldEndo (Endo (+1)) [(+2), (*3)] `appEndo` 1
-- 6
--
-- Above can be seen as:
--
-- >>> (+1) . (+2) . (*3) $ 1
-- 6
foldEndo :: FoldEndoArgs args => args
foldEndo = foldEndoArgs mempty

-- | Same as 'foldEndo', but folds endomorphisms in reverse order.
--
-- Following are the same examples as for 'foldEndo' function. Please, note the
-- differences in results.
--
-- Order in which endomorphisms are folded is reversed:
--
-- >>> dualFoldEndo (Endo (1:)) [(2:), (3:)] `appEndo` []
-- [2,3,1]
--
-- For numbers it would look like:
--
-- >>> dualFoldEndo (Endo (+1)) [(+2), (*3)] `appEndo` 1
-- 12
--
-- Above can be seen as:
--
-- >>> (*3) . (+2) . (+1) $ 1
-- 12
dualFoldEndo :: FoldEndoArgs args => args
dualFoldEndo = dualFoldEndoArgs mempty

-- {{{ FoldEndoArgs Type Class ------------------------------------------------

class FoldEndoArgs a where
    type ResultOperatesOn a
    foldEndoArgs     ::       Endo (ResultOperatesOn a)  -> a
    dualFoldEndoArgs :: Dual (Endo (ResultOperatesOn a)) -> a
#ifdef HAVE_MINIMAL_PRAGMA
    {-# MINIMAL foldEndoArgs, dualFoldEndoArgs #-}
#endif

instance
    ( AnEndo a
    , FoldEndoArgs r
    , EndoOperatesOn a ~ ResultOperatesOn r
    ) => FoldEndoArgs (a -> r)
  where
    type ResultOperatesOn (a -> r) = ResultOperatesOn r
    foldEndoArgs     e e' = foldEndoArgs     (e <> anEndo    e')
    dualFoldEndoArgs e e' = dualFoldEndoArgs (e <> aDualEndo e')

instance FoldEndoArgs (Endo a) where
    type ResultOperatesOn (Endo a) = a
    foldEndoArgs              = id
    dualFoldEndoArgs (Dual e) = e

instance FoldEndoArgs (Dual (Endo a)) where
    type ResultOperatesOn (Dual (Endo a)) = a
    foldEndoArgs     = Dual
    dualFoldEndoArgs = id

instance FoldEndoArgs r => FoldEndoArgs (Either e r) where
    type ResultOperatesOn (Either e r) = ResultOperatesOn r
    foldEndoArgs     = Right . foldEndoArgs
    dualFoldEndoArgs = Right . dualFoldEndoArgs

instance FoldEndoArgs r => FoldEndoArgs (Identity r) where
    type ResultOperatesOn (Identity r) = ResultOperatesOn r
    foldEndoArgs     = Identity . foldEndoArgs
    dualFoldEndoArgs = Identity . dualFoldEndoArgs

instance FoldEndoArgs r => FoldEndoArgs (IO r) where
    type ResultOperatesOn (IO r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance FoldEndoArgs r => FoldEndoArgs (Maybe r) where
    type ResultOperatesOn (Maybe r) = ResultOperatesOn r
    foldEndoArgs     = Just . foldEndoArgs
    dualFoldEndoArgs = Just . dualFoldEndoArgs

-- {{{ Transformers -----------------------------------------------------------

-- {{{ Functor Transformers ---------------------------------------------------

instance
    (Applicative f, Applicative g, FoldEndoArgs r)
    => FoldEndoArgs (Compose f g r)
  where
    type ResultOperatesOn (Compose f g r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
    (Applicative f, Applicative g, FoldEndoArgs r)
    => FoldEndoArgs (Product f g r)
  where
    type ResultOperatesOn (Product f g r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

-- }}} Functor Transformers ---------------------------------------------------

-- {{{ Monad Transformers -----------------------------------------------------

instance (Applicative f, FoldEndoArgs r) => FoldEndoArgs (IdentityT f r) where
    type ResultOperatesOn (IdentityT f r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

#if HAVE_EXCEPTT
instance (Applicative f, FoldEndoArgs r) => FoldEndoArgs (ExceptT e f r) where
    type ResultOperatesOn (ExceptT e f r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs
#endif

instance (Applicative f, FoldEndoArgs r) => FoldEndoArgs (ListT f r) where
    type ResultOperatesOn (ListT f r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
#ifdef APPLICATIVE_MONAD
    ( Monad m
#else
    ( Functor m
    , Monad m
#endif
    , FoldEndoArgs r
    ) => FoldEndoArgs (MaybeT m r) where
    type ResultOperatesOn (MaybeT m r) = ResultOperatesOn r
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance (Applicative f, FoldEndoArgs r) => FoldEndoArgs (ReaderT r' f r) where
    type ResultOperatesOn (ReaderT r' f r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
#if APPLICATIVE_MONAD
    ( Functor m
    , Monad m
#else
    ( Monad m
#endif
    , Monoid w
    , FoldEndoArgs r
    ) => FoldEndoArgs (RWST r' w s m r)
  where
    type ResultOperatesOn (RWST r' w s m r) = ResultOperatesOn r
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance
#ifndef APPLICATIVE_MONAD
    ( Functor m
    , Monad m
#else
    ( Monad m
#endif
    , Monoid w
    , FoldEndoArgs r
    ) => FoldEndoArgs (Strict.RWST r' w s m r)
  where
    type ResultOperatesOn (Strict.RWST r' w s m r) = ResultOperatesOn r
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance (Monad m, FoldEndoArgs r) => FoldEndoArgs (StateT s m r) where
    type ResultOperatesOn (StateT s f r) = ResultOperatesOn r
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance (Monad m, FoldEndoArgs r) => FoldEndoArgs (Strict.StateT s m r) where
    type ResultOperatesOn (Strict.StateT s f r) = ResultOperatesOn r
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance
    (Applicative f, FoldEndoArgs r, Monoid w) => FoldEndoArgs (WriterT w f r)
  where
    type ResultOperatesOn (WriterT w f r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
    (Applicative f, FoldEndoArgs r, Monoid w)
    => FoldEndoArgs (Strict.WriterT w f r)
  where
    type ResultOperatesOn (Strict.WriterT w f r) = ResultOperatesOn r
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

-- }}} Monad Transformers -----------------------------------------------------

-- }}} Transformers -----------------------------------------------------------

-- {{{ FoldEndoArgs Type Class ------------------------------------------------

-- {{{ AnEndo Type Class ------------------------------------------------------

class AnEndo a where
    type EndoOperatesOn a

    anEndo    :: a -> Endo (EndoOperatesOn a)

    aDualEndo :: a -> Dual (Endo (EndoOperatesOn a))
    aDualEndo = Dual . anEndo

#if HAVE_MINIMAL_PRAGMA
    {-# MINIMAL anEndo #-}
#endif

instance AnEndo (Endo a) where
    type EndoOperatesOn (Endo a) = a
    anEndo = id

instance AnEndo (a -> a) where
    type EndoOperatesOn (a -> a) = a
    anEndo = Endo

instance AnEndo a => AnEndo (Maybe a) where
    type EndoOperatesOn (Maybe a) = EndoOperatesOn a

    anEndo Nothing  = mempty
    anEndo (Just e) = anEndo e

-- {{{ Foldable Instances -----------------------------------------------------

-- | Wrapper for 'Foldable' instances.
--
-- This allows using 'foldEndo' and 'dualFoldEndo' for any 'Foldable' instance
-- without the need for @OverlappingInstances@ language extension.
newtype WrappedFoldable f a = WrapFoldable {getFoldable :: f a}
    deriving (Data, Generic, Read, Show, Typeable)

instance (Foldable f, AnEndo a) => AnEndo (WrappedFoldable f a) where
    type EndoOperatesOn (WrappedFoldable f a) = EndoOperatesOn a
    anEndo    (WrapFoldable fa) = foldMap anEndo    fa
    aDualEndo (WrapFoldable fa) = foldMap aDualEndo fa

instance AnEndo a => AnEndo [a] where
    type EndoOperatesOn [a] = EndoOperatesOn a
    anEndo    = anEndo    . WrapFoldable
    aDualEndo = aDualEndo . WrapFoldable

-- {{{ Transformers -----------------------------------------------------------

-- | Fold in reverese order.
instance (Foldable f, AnEndo a) => AnEndo (Reverse f a) where
    type EndoOperatesOn (Reverse f a) = EndoOperatesOn a
    anEndo    = anEndo    . WrapFoldable
    aDualEndo = aDualEndo . WrapFoldable

-- }}} Transformers -----------------------------------------------------------

-- }}} Foldable Instances -----------------------------------------------------

-- {{{ Instances For Tuples ---------------------------------------------------

instance
    ( AnEndo a
    , AnEndo b
    , EndoOperatesOn a ~ EndoOperatesOn b
    ) => AnEndo (a, b)
  where
    type EndoOperatesOn (a, b) = EndoOperatesOn a
    anEndo    (a, b) = anEndo    a <> anEndo    b
    aDualEndo (a, b) = aDualEndo a <> aDualEndo b

instance
    ( AnEndo a
    , AnEndo b
    , AnEndo c
    , EndoOperatesOn a ~ EndoOperatesOn b
    , EndoOperatesOn a ~ EndoOperatesOn c
    ) => AnEndo (a, b, c)
  where
    type EndoOperatesOn (a, b, c) = EndoOperatesOn a
    anEndo    (a, b, c) = anEndo    a <> anEndo    b <> anEndo    c
    aDualEndo (a, b, c) = aDualEndo a <> aDualEndo b <> aDualEndo c

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    ) => AnEndo (a1, a2, a3, a4)
  where
    type EndoOperatesOn (a1, a2, a3, a4) = EndoOperatesOn a1
    anEndo (a1, a2, a3, a4) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        ]

    aDualEndo (a1, a2, a3, a4) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    ) => AnEndo (a1, a2, a3, a4, a5)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        ]

    aDualEndo (a1, a2, a3, a4, a5) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    ) => AnEndo (a1, a2, a3, a4, a5, a6)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , AnEndo a8
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a8
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7, a8)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7, a8) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7, a8) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        , anEndo a8
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7, a8) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        , aDualEndo a8
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , AnEndo a8
    , AnEndo a9
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a8
    , EndoOperatesOn a1 ~ EndoOperatesOn a9
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7, a8, a9) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        , anEndo a8
        , anEndo a9
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        , aDualEndo a8
        , aDualEndo a9
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , AnEndo a8
    , AnEndo a9
    , AnEndo a10
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a8
    , EndoOperatesOn a1 ~ EndoOperatesOn a9
    , EndoOperatesOn a1 ~ EndoOperatesOn a10
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        , anEndo a8
        , anEndo a9
        , anEndo a10
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        , aDualEndo a8
        , aDualEndo a9
        , aDualEndo a10
        ]

-- }}} Instances For Tuples ---------------------------------------------------
-- }}} AnEndo Type Class ------------------------------------------------------

-- {{{ Utility Functions ------------------------------------------------------

-- | Variant of function @'$' :: (a -> b) -> a -> b@ from "Data.Function"
-- module, but with fixity as @(&) :: a -> (a -> b) -> b@ function from
-- <http://hackage.haskell.org/package/lens lens> package.
(&$) :: (a -> b) -> a -> b
f &$ a = f a
infixl 1 &$

-- }}} Utility Functions ------------------------------------------------------

-- $usageExample
--
-- TODO
