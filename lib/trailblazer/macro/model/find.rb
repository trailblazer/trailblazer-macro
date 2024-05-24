module Trailblazer
  module Macro
    class Model
      # New API for retrieving models by ID.
      # Only handles keyword argument style.
      def self.Find(model_class, positional_method = nil, params_key: nil, id: "model.find", not_found_terminus: false, **keyword_options, &block)
        raise "unknown options #{keyword_options}" if keyword_options.size > 1

        task =
          if positional_method
            finder_activity_for(
              params_key: params_key || :id,
              finder:     Find::Positional.new(model_class: model_class, find_method: positional_method),
              &block
            )
          else
            find_method_name, column_key = keyword_options.to_a[0]

            params_key ||= column_key

            finder_activity_for(
              params_key: params_key,
              finder:     Find::KeywordArguments.new(model_class: model_class, find_method: find_method_name, column_key: column_key),
              &block
            )
          end

        options = options_for(task, id: id)

        options = options.merge(Activity::Railway.Output(:failure) => Activity::Railway.End(:not_found)) if not_found_terminus

        options
      end

      def self.options_for(task, id:)
        options = Activity::Railway.Subprocess(task).merge(id: id)

        inject = {
          Activity::Railway.Inject() => [:params], # pass-through {:params} if it's in ctx.
        }

        out = { # TODO: use Outject once it is implemented.
          Activity::Railway.Out() => ->(ctx, **) { ctx.key?(:model) ? {model: ctx[:model]} : {} }
        }

        options = options.merge(inject)
        options = options.merge(out)
      end

      # Finder activity consists of two steps:
      # {extract_id}, and the finder code.
      #
      #   |-- model.build
      #   |   |-- Start.default
      #   |   |-- extract_id
      #   |   |-- finder.Trailblazer::Macro::Model::Find::Positional
      #   |   `-- End.success
      #   |-- validate
      def self.finder_activity_for(params_key:, finder:, **, &block)
        id_from =
          if block
            block
          else
            ->(ctx, params: {}, **) { params[params_key] } # default id_from
          end

        extract_id = Macro.task_adapter_for_decider(id_from, variable_name: :id)

        Class.new(Activity::Railway) do
          step task: extract_id, id: :extract_id
          step finder,           id: "finder.#{finder.class}" # FIXME: discuss ID.
        end
      end

      # Runtime code.
      module Find
        class Positional
          def initialize(model_class:, find_method:)
            @model_class = model_class
            @find_method = find_method
          end

          def call(ctx, id:, **)
            ctx[:model] = @model_class.send(@find_method, id)
          end
        end

        class KeywordArguments
          def initialize(model_class:, find_method:, column_key:)
            @model_class = model_class
            @find_method = find_method
            @column_key  = column_key.to_sym
          end

          def call(ctx, id:, **)
            ctx[:model] = @model_class.send(@find_method, @column_key => id)
          end
        end

        class NoArgument < Positional
          def call(ctx, **)
            ctx[:model] = @model_class.send(@find_method)
          end
        end
      end # Find

      def self.Build(model_class, method = :new, id: "model.build")
        activity = Class.new(Activity::Railway) do
          step Find::NoArgument.new(model_class: model_class, find_method: method)
        end

        options_for(activity, id: id)
      end
    end
  end
end