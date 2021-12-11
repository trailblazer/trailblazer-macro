# Trailblazer Macro
![Build
Status](https://github.com/trailblazer/trailblazer-macro/actions/workflows/ci.yml/badge.svg?branch=master)
[![Gem Version](https://badge.fury.io/rb/trailblazer-macro.svg)](http://badge.fury.io/rb/trailblazer-macro)
All common Macro's for Trailblazer::Operation, will come here

## TODO
Describe the following Macro's:
- Nested
- Rescue
- Wrap

## Table of Contents
- [Model Macro](#model-macro)
- [Policy Macro](#policy-macro)
  * [Policy::Pundit - Macro](#policy--pundit---macro)
    + [Policy::Pundit - API](#policy--pundit---api)
    + [Policy::Pundit - Name](#policy--pundit---name)
    + [Policy::Pundit - Dependency Injection](#policy--pundit---dependency-injection)
  * [Policy::Guard - Macro](#policy--guard---macro)
    + [Policy::Guard - API](#policy--guard---api)
    + [Policy::Guard - Callable](#policy--guard---callable)
    + [Policy::Guard - Instance Method](#policy--guard---instance-method)
    + [Policy::Guard - Name](#policy--guard---name)
    + [Policy::Guard - Dependency Injection](#policy--guard---dependency-injection)
    + [Policy::Guard - Position](#policy--guard---position)

## Model Macro
Trailblazer also has a convenient Macro to handle model creation and basic finding by id. The Model macro literally does what our model! step did.

```ruby
class Song::Create < Trailblazer::Operation
  step Policy::Guard( :authorize! )
  step Model( Song, :new )
end
```

Note that Model is not designed for complex query logic - should you need that, you might want to use [Trailblazer Finder][trailblazer_finder_link] or simply write your own customized step.

Due to a lot of requests, we have adjusted the `:find_by` method so you can specify a key to find by.
```ruby
class Song::Create < Trailblazer::Operation
  step Policy::Guard( :authorize! )
  step Model( Song, :find_by, :title )
end
```
Not specifying the third parameter in the Model Macro for `:find_by`, will result in defaulting it back to `:id`.

[trailblazer-finder-link]: https://github.com/trailblazer/trailblazer-finder/

## Policy Macro
An optional Policy Macro for Trailblazer Operations that blocks unauthorized users from running the operation.

You can abort running an operation using a policy. "Pundit-style" policy classes define the rules.
```ruby
class Comment::Policy
  def initialize(user, comment)
    @user, @comment = user, comment
  end

  def create?
    @user.admin?
  end
end
```

The rule is enabled via the ::policy call.
```ruby
class Comment::Create < Trailblazer::Operation
  step Policy( Comment::Policy, :create? )
end
```

The policy is evaluated in #setup!, raises an exception if false and suppresses running #process.

### Policy::Pundit - Macro
The Policy::Pundit Macro allows using Pundit-compatible policy classes in an operation.

A Pundit policy has various rule methods and a special constructor that receives the current user and the current model.
```ruby
class MyPolicy
  def initialize(user, model)
    @user, @model = user, model
  end

  def create?
    @user == Module && @model.id.nil?
  end

  def new?
    @user == Class
  end
end
```

In pundit policies, it is a convention to have access to those objects at runtime and build rules on top of those.

You can plug this policy into your pipe at any point. However, this must be inserted after the "model" skill is available.
```ruby
class Create < Trailblazer::Operation
  step Model( Song, :new )
  step Policy::Pundit( MyPolicy, :create? )
  # ...
end
```

Note that you don’t have to create the model via the Model macro - you can use any logic you want. The Pundit macro will grab the model from ["model"], though.

This policy will only pass when the operation is invoked as follows.
```ruby
Create.( {}, "current_user" => User.find(1) )
```

Any other call will cause a policy breach and stop the pipe from executing after the Policy::Pundit step.

#### Policy::Pundit - API
Add your polices using the Policy::Pundit macro. It accepts the policy class name, and the rule method to call.
```ruby
class Create < Trailblazer::Operation
  step Model( Song, :new )
  step Policy::Pundit( MyPolicy, :create? )
  # ...
end
```

The step will create the policy instance automatically for you and passes the "model" and the "current_user" skill into the policies constructor. Just make sure those dependencies are available before the step is executed.

If the policy returns falsey, it deviates to the left track.

After running the Pundit step, its result is readable from the Result object.
```ruby
result = Create.({}, "current_user" => Module)
result["result.policy.default"].success? #=> true
result["result.policy.default"]["policy"] #=> #<MyPolicy ...>
```

Note that the actual policy instance is available via ["result.policy.#{name}"]["policy"] to be reinvoked with other rules (e.g. in the view layer).

#### Policy::Pundit - Name
You can add any number of Pundit policies to your pipe. Make sure to use name: to name them, though.
```ruby
class Create < Trailblazer::Operation
  step Model( Song, :new )
  step Policy::Pundit( MyPolicy, :create?, name: "after_model" )
  # ...
end
```

The result will be stored in "result.policy.#{name}"
```ruby
result = Create.({}, "current_user" => Module)
result["result.policy.after_model"].success? #=> true
```

#### Policy::Pundit - Dependency Injection
Override a configured policy using dependency injection.
```ruby
Create.({},
  "current_user"        => Module,
  "policy.default.eval" => Trailblazer::Operation::Policy::Pundit.build(AnotherPolicy, :create?)
)
```
You can inject it using "policy.#{name}.eval". It can be any object responding to call.

### Policy::Guard - Macro
A guard is a step that helps you evaluating a condition and writing the result. If the condition was evaluated as falsey, the pipe won’t be further processed and a policy breach is reported in Result["result.policy.default"].

```ruby
class Create < Trailblazer::Operation
  step Policy::Guard( ->(options, params:, **) { params[:pass] } )
  step :process

  def process(*)
    self["x"] = true
  end
end
```

The only way to make the above operation invoke the second step :process is as follows.
```ruby
result = Create.({ pass: true })
result["x"] #=> true
```

Any other input will result in an abortion of the pipe after the guard.
```ruby
result = Create.()
result["x"] #=> nil
result["result.policy.default"].success? #=> false
```

#### Policy::Guard - API
The Policy::Guard macro helps you inserting your guard logic. If not defined, it will be evaluated where you insert it.
```ruby
class Create < Trailblazer::Operation
  step Policy::Guard( ->(options, params:, **) { params[:pass] } )
  # ...
end
```
The options object is passed into the guard and allows you to read and inspect data like params or current_user. Please use kw args.

#### Policy::Guard - Callable
As always, the guard can also be a Callable-marked object.
```ruby
class MyGuard
  include Uber::Callable

  def call(options, params:, **)
    params[:pass]
  end
end
```

Insert the object instance via the Policy::Guard macro.
```ruby
class Create < Trailblazer::Operation
  step Policy::Guard( MyGuard.new )
  # ...
end
```

#### Policy::Guard - Instance Method
As always, you may also use an instance method to implement a guard.
```ruby
class Create < Trailblazer::Operation
  step Policy::Guard( :pass? )

  def pass?(options, params:, **)
    params[:pass]
  end
  # ...
end
```

#### Policy::Guard - Name
The guard name defaults to default and can be set via name:. This allows having multiple guards.
```ruby
class Create < Trailblazer::Operation
  step Policy::Guard( ->(options, current_user:, **) { current_user }, name: :user )
  # ...
end
```

The result will sit in result.policy.#{name}.
```ruby
result = Create.({}, "current_user" => true)
result["result.policy.user"].success? #=> true
```

#### Policy::Guard - Dependency Injection
Instead of using the configured guard, you can inject any callable object that returns a Result object. Do so by overriding the policy.#{name}.eval path when calling the operation.
```ruby
Create.({},
  "current_user"        => Module,
  "policy.default.eval" => Trailblazer::Operation::Policy::Guard.build(->(options) { false })
)
```
An easy way to let Trailblazer build a compatible object for you is using Guard.build.

This is helpful to override a certain policy for testing, or to invoke it with special rights, e.g. for an admin.

#### Policy::Guard - Position
You may specify a position.
```ruby
class Create < Trailblazer::Operation
  step :model!
  step Policy::Guard( :authorize! ), before: :model!
end
```

Resulting in the guard inserted before model!, even though it was added at a later point.
```ruby
puts Create["pipetree"].inspect(style: :rows) #=>
 # 0 ========================>operation.new
 # 1 ==================>policy.default.eval
 # 2 ===============================>model!
```
This is helpful if you maintain modules for operations with generic steps.
