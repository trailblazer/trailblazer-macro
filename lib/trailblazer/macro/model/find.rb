module Trailblazer
  module Macro
    class Model
      # New API for retrieving models by ID.
      # Only handles keyword argument style.
      #
      #
      # DESIGN NOTES
      #   * params[:id] extraction and the actual query are two separate components in the final finder activity.
      def self.Find(model_class, positional_method = nil, find_method: nil, id: "model.find", not_found_terminus: false, query: nil, **keyword_options, &block)
      # 1. optional: translate kws/positionals into local kws
      # 2. build :query
      # 3. build find activity

        # raise "unknown options #{keyword_options}" if keyword_options.size > 1

        params_key, block, finder_step_options =
          if positional_method
            bla_explicit_positional(model_class, positional_method, **keyword_options, &block) # FIXME: test block
          elsif find_method.nil? && query.nil? # translate_from_shorthand
            bla_shorthand(model_class, **keyword_options, &block)
          else # options passed explicitly, kws. this still means we need to translate find_method to query, or use user's query.
            # TODO: sort out query: default it or take user's

            if query.nil?
              blubb_bla_keywords(model_class, find_method: find_method, **keyword_options, &block)
            else
              # raise "IMPLEMENT ME"
              blubb_bla_query(model_class, query, **keyword_options, &block)
            end
          end

        task = finder_activity_for(
          params_key: params_key,
          finder:     finder_step_options,
          &block
        )

        options = options_for(task, id: id)

        options = options.merge(Activity::Railway.Output(:failure) => Activity::Railway.End(:not_found)) if not_found_terminus

        options
      end

      # Defaulting happening.
      def self.normalize_keys(column_key: :id, params_key: column_key, **)
        return params_key, column_key
      end

      def self.bla_shorthand(model_class, **options, &block)
        # translate shorthand form.
        find_method_name, column_key = options.to_a[0]

        params_key = options.key?(:params_key) ? options[:params_key] : column_key # TODO: use method for this.

        [
          params_key,
          block,
          Find::KeywordArguments.new(model_class: model_class, find_method: find_method_name, column_key: column_key),
        ]
      end

      def self.bla_explicit_positional(model_class, positional_method, **options, &block)
        params_key, _ = normalize_keys(**options)

        [
          params_key,
          block,
          Find::Positional.new(model_class: model_class, find_method: positional_method), # query
        ]
      end

      def self.blubb_bla_keywords(model_class, find_method:, **options, &block) # FIXME: defaulting is redundant with bla_explicit_positional.
        params_key, column_key = normalize_keys(**options)

        finder = Find::KeywordArguments.new(model_class: model_class, find_method: find_method, column_key: column_key)

        [params_key, block, finder]
      end

      def self.blubb_bla_query(model_class, query, column_key: :id, params_key: column_key, **, &block) # FIXME: defaulting is redundant with bla_explicit_positional.
        query_on_model_class = ->(ctx, **kws) { model_class.instance_exec(ctx, **kws, &query) } # FIXME: we can only use procs here. what about methods, classes etc?

        finder = Macro.task_adapter_for_decider(query_on_model_class, variable_name: :model) # FIXME: {:model} is hard-coded.

        [
          params_key,
          block,
          {task: finder} # circuit interface for the Task::Adapter.
        ]
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
