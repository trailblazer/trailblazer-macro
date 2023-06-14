# 2.1.15

* Use `Macro.id_for` for `Rescue`, meaning IDs will now be consistent à la `Rescue/1` instead of `Rescue(1)`.
* In `Each`'s tracing code, use `developer-0.1.0` API.
* Use `trailblazer-operation-0.10.1`.

# 2.1.14

* Use `trailblazer-activity-dsl-linear-1.2.0` and change internal API as required.

# 2.1.13

* Fix an introspect bug in `Each()` where we couldn't look into `"invoke_block_activity"`.

# 2.1.12

## Internals

* Introduce `AssignVariable`.
* Use trailblazer-activity-dsl-linear-1.1.0.

## Each()

* Introducing the `Each()` macro to iterate over datasets while invoking a particular operation, as if
  they were run as separate serially connected operations.

## Nested()

* Restructured internals, it's much more readable, `Dynamic` and `Static` are completely separated now.
* `Static` handles `:auto_wire` and allows to route any nested terminus. This was not possible before,
  you only had `FastTrack` generic termini.
* Better warning when using `Nested(Operation)` without a dynamic decider.
* Internal structure of `Nested()` has changed, the trace looks different.

## Wrap()

* Now implements patching.

## Model()

* Remove `ctx[:"result.model"]`.
* Don't set `ctx[:model]` unless `Builder` returns a model.

# 2.1.11

* In `Nested()`, we no longer use `Railway::End::Success` and `Railway::End::Failure` as static outputs but
  simply use `Railway`'s default termini objects.
* Use `dsl`'s new `Inject()` API instead of a overriding `:inject` in `Model()` and `Policy()`.

# 2.1.10

* Yanked, pushed accidentially.

# 2.1.9

* Allow omitting `:params` when calling the operation by defaulting it to `{}` in `Model()`.
* Use `dsl-linear` 0.5.0 and above, which allows removing `Inject()` uses.

# 2.1.8

Yanked due to inconsistency.

# 2.1.7

* Improve `Nested()` warning message.
* Fix exception in `Rescue()` macro when it's handler is a `Module`.

# 2.1.6

* Allow connecting ends of the dynamically selected activity for `Nested()` using `:auto_wire`.

# 2.1.5

* Support for Ruby 3.0.

# 2.1.4

* Upgrade DSL version to fix step's circuit interface eating passed arguments
* Upgrade OP version to remove OP::Container reference in tests

# 2.1.3

* Rename Model()'s `not_found_end` kwarg to `not_found_terminus` for consistency.

# 2.1.2

* Fix to make macros available in all Linear::DSL strategies.
* Make `params` optional in `Model`.
* Support for adding `End.not_found` end in `Model`.

# 2.1.1

* Fix case when Macros generate same id due to small entropy

# 2.1.0

* Finally.

# 2.1.0.rc14

* Remove the explicit `dsl-linear` dependency.

# 2.1.0.rc13

* Use symbol keys on `ctx`, only.

# 2.1.0.rc12

* Dependency bumps.

# 2.1.0.rc11

* Works with `>= activity-0.8`.
* Implement old functionality of `Nested()`.

# 2.1.0.rc1

* Use `operation-0.4.1`.
* Change back to MIT license.

# 2.1.0.beta7

* Nested :input, :output now uses activity's VariableMapping.

# 2.1.0.beta6

* Use newest operation.

# 2.1.0.beta5

# 2.1.0.beta4

* New operation version.

# 2.1.0.beta3

* Fix `Wrap` which didn't deprecate `Module`s properly.

# 2.1.0.beta2

* Move all code related to DSL (`ClassDependencies`) back to the `trailblazer` gem.
* Configurable field key for the `Model()` macro

# 2.1.0.beta1

* First release into an unsuspecting world. Goal is to have this gem decoupled from any Representable and Reform dependencies.
