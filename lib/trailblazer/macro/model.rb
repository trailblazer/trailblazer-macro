module Trailblazer
  module Macro

      # TODO: deprecate find_by_key in favor of `find_by: :id`
    def self.Model(model_class = nil, action = :new, find_by_key = :id, id: "model.build", not_found_terminus: false, params_key: nil, id_from: nil, **options)
      # {find_by: :slug}
      if options.any?
        raise "unknown options #{options}" if options.size > 1
        action, find_by_key = options.to_a[0]

        params_key ||= find_by_key

        id_from =
          if id_from.nil?
            ->(ctx, params:, **) { params[params_key] } # default id_from
          else
            id_from
          end

        extract_id = Macro.task_adapter_for_decider(id_from, variable_name: :id)

        task = Activity::Railway() do
          step task: extract_id, id: :extract_id
          step Model.method(:produce)
        end

        options = Activity::Railway.Subprocess(task)
      else # old style, deprecate
        task = Activity::Circuit::TaskAdapter.for_step(Model.new)

        options = {task: task, id: id}
      end

      inject = {
        Activity::Railway.Inject() => [:params], # pass-through {:params} if it's in ctx.

        # defaulting as per Inject() API.
        Activity::Railway.Inject() => {
          :"model.class"          => ->(*) { model_class },
          :"model.action"         => ->(*) { action },
          :"model.find_by_key"    => ->(*) { find_by_key },
          :"model.id_from"        => ->(*) { id_from }, # TODO: test me.
        },
      }

      out = { # TODO: use Outject once it is implemented.
        Activity::Railway.Out() => ->(ctx, **) { ctx.key?(:model) ? {model: ctx[:model]} : {} }
      }

      options = options.merge(inject)
      options = options.merge(out)


      options = options.merge(Activity::Railway.Output(:failure) => Activity::Railway.End(:not_found)) if not_found_terminus

      options
    end

    class Model
      def self.produce(ctx, id:, **)
        model_class   = ctx[:"model.class"]
        find_by_key   = ctx[:"model.find_by_key"]

        ctx[:model] = model_class.find_by(find_by_key.to_sym => id)
      end

      def call(ctx, params: {}, **)
        builder = Builder.new
        model   = builder.call(ctx, params) or return

        ctx[:model] = model
      end

      class Builder
        def call(ctx, params)
          action        = ctx[:"model.action"]
          model_class   = ctx[:"model.class"]
          find_by_key   = ctx[:"model.find_by_key"]
          id_from       = ctx[:"model.id_from"]
          action        = :pass_through unless %i[new find_by].include?(action)

          send("#{action}!", model_class, params, ctx[:"model.action"], find_by_key)
        end

        def new!(model_class, params, *)
          model_class.new
        end

        # Doesn't throw an exception and will return false to divert to Left.
        def find_by!(model_class, params, action, find_by_key, *)
          model_class.find_by(find_by_key.to_sym => params[find_by_key])
        end

        # Call any method on the model class and pass find_by_key, for example find(params[:id]).
        def pass_through!(model_class, params, action, find_by_key, *)
          model_class.send(action, params[find_by_key])
        end
      end
    end
  end # Macro
end
