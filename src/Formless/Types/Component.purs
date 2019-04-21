module Formless.Types.Component where

import Prelude

import Data.Const (Const)
import Data.Functor.Variant (VariantF, FProxy)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.Maybe (Maybe)
import Data.Newtype (class Newtype)
import Data.Symbol (SProxy(..))
import Data.Tuple (Tuple)
import Data.Variant (Variant)
import Effect.Aff (Fiber, Milliseconds)
import Effect.Aff.AVar (AVar)
import Effect.Ref (Ref)
import Formless.Types.Form (FormField, InputField, InputFunction, OutputField, U)
import Formless.Validation (Validation)
import Type.Row (type (+))
import Halogen as H
import Halogen.HTML as HH
import Halogen.Query.ChildQuery (ChildQueryBox)

-- | A type representing the various functions that can be provided to extend 
-- | the Formless component. Usually only the `render` function is required,
-- | but you may also provide others. For example, if you have child components,
-- | you can tell Formless how to manage those child components by adding a
-- | handler action and `handleAction` case.
type Spec form st query act ps msg m =
  { render :: PublicState form st -> ComponentHTML form act ps m
  , handleAction :: act -> HalogenM form st act ps msg m Unit
  , handleQuery :: forall a. query a -> HalogenM form st act ps msg m (Maybe a)
  , handleMessage :: Message form st -> HalogenM form st act ps msg m Unit
  , receive :: Input form st m -> Maybe act
  , initialize :: Maybe act
  , finalize :: Maybe act
  }

-- | A simplified type when the component has only a form spec, some output, and runs
-- | in some monad `m`
type Spec' form msg m = Spec form () (Const Void) Void () msg m

-- | The component action type. While actions are typically considered
-- | internal to a component, in Formless you write the render function and will
-- | need to be able to use these directly. Many of these are shared with queries
-- | of the same name so they can be used either as queries or as actions. See
-- | `Formless.Action` and `Formless.Query`.
-- |
-- | You can freely extend this type with your own actions using `injAction`.
type Action form act = Variant
  ( userAction :: act
  | InternalAction act 
  + PublicAction form 
  )

type PublicAction form =
  ( modify :: form Variant InputFunction
  , validate :: form Variant U
  , modifyValidate :: Tuple (Maybe Milliseconds) (form Variant InputFunction)
  , reset :: form Variant InputFunction
  , setAll :: Tuple (form Record InputField) Boolean
  , modifyAll :: Tuple (form Record InputFunction) Boolean
  , validateAll :: Unit
  , resetAll :: Unit
  , submit :: Unit
  , loadForm :: form Record InputField
  )

type InternalAction act r =
  ( initialize :: Maybe act
  , syncFormData :: Unit
  | r
  )

-- | A simple action type when the component does not need extension
type Action' form = Action form Void

-- | The internals of the public component query type. Many of these are shared 
-- | with actions of the same name so they can be used in rendering. See 
-- | `Formless.Action` and `Formless.Query` for more.
data QueryF form ps a
  = SubmitReply (Maybe (form Record OutputField) -> a)
  -- Query a child component of Formless through Formless
  | SendQuery (ChildQueryBox ps (Maybe a))
  -- Run a Formless action as a query
  | AsQuery (Variant (PublicAction form)) a

derive instance functorQueryF :: Functor (QueryF form ps)

-- | The component query type, which you can freely extend with your own queries
-- | using `injQuery` from `Formless.Query`.
type Query form query ps = VariantF
  ( query :: FProxy (QueryF form ps) 
  , userQuery :: FProxy query
  )

-- | A simple query type when the component does not need extension
type Query' form = Query form (Const Void) ()

-- | The component type
type Component form st query ps msg m = 
  H.Component HH.HTML (Query form query ps) (Input form st m) msg m

-- | A simple component type when the component does not need extension
type Component' form m =
  Component form () (Const Void) () Void m

-- | The component's HTML type, the result of the render function.
type ComponentHTML form act ps m = 
  H.ComponentHTML (Action form act) ps m

-- | A simple component HTML type when the component does not need extension
type ComponentHTML' form m =
  ComponentHTML form Void () m

-- | The component's eval type
type HalogenM form st act ps msg m =
  H.HalogenM (State form st m) (Action form act) ps msg m

-- | A simple component eval type when the component does not need extension
type HalogenM' form m =
  HalogenM form () Void () Void m

-- | The component local state
type State form st m = 
  {| StateRow form (internal :: InternalState form m | st) }

-- | A simple state type when the component does not need extension
type State' form m =
  State form () m

-- | The component's public state
type PublicState form st = 
  {| StateRow form st }

-- | The component's public state, as an extensible row
type StateRow form st =
  ( validity :: ValidStatus
  , dirty :: Boolean
  , submitting :: Boolean
  , errors :: Int
  , submitAttempts :: Int
  , form :: form Record FormField
  | st
  )

-- | A newtype to make easier type errors for end users to
-- | read by hiding internal fields
newtype InternalState form m = InternalState
  { initialInputs :: form Record InputField
  , validators :: form Record (Validation form m)
  , allTouched :: Boolean
  , debounceRef :: Maybe (Ref (Maybe Debouncer))
  , validationRef :: Maybe (Ref (Maybe H.ForkId))
  }

derive instance newtypeInternalState :: Newtype (InternalState form m) _

-- | A type to represent a running debouncer
type Debouncer =
  { var :: AVar Unit
  , fiber :: Fiber Unit
  }

-- | A type to represent validation status
data ValidStatus
  = Invalid
  | Incomplete
  | Valid

derive instance genericValidStatus :: Generic ValidStatus _
derive instance eqValidStatus :: Eq ValidStatus
derive instance ordValidStatus :: Ord ValidStatus

instance showValidStatus :: Show ValidStatus where
  show = genericShow

-- | A type to represent whether inputs should be generated from default `Initial`
-- | values or whether they will be provided manually.
data InitialInputs form 
  = Defaults
  | Custom (form Record InputField) 

-- | The component's input type. If you provide `Nothing` as your `initialInputs`
-- | then the form will fill in values based on the `Initial` type class for the
-- | field's input type. Otherwise, the form will contain the values you provide.
-- |
-- | Validators can be created using the Formless.Validation module.
type Input form st m =
  { initialInputs :: InitialInputs form
  , validators :: form Record (Validation form m)
  | st
  }

-- | A simple Input type when the component does not need extension
type Input' form m = Input form () m

-- | The component tries to require as few messages to be handled as possible. You
-- | can always use the *Reply variants of queries to perform actions and receive
-- | a result out the other end, or extend these messages.
data Message form st
  = Submitted (form Record OutputField)
  | Changed (PublicState form st)

type Message' form = Message form ()

-- | A slot type that can be used in the ChildSlots definition for your parent
-- | component
type Slot form query ps msg = H.Slot (Query form query ps) msg

-- | A simple Slot type when the component does not need extension
type Slot' form = H.Slot (Query' form) Void

-- | A convenience export of formless as a symbol for use when mounting Formless
-- | as a child component
-- |
-- | ```purescript
-- | type ChildSlots = (formless :: F.Slot' Form)
-- | HH.slot F._formless unit (F.component spec) input handler
-- | ```
_formless = SProxy :: SProxy "formless"
