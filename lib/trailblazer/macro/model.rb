module Trailblazer::Macro
  def self.Model(model_class, action = nil, find_by_key = nil)
    task = Trailblazer::Activity::TaskBuilder::Binary(Model.new)

    injection = Trailblazer::Activity::TaskWrap::Inject::Defaults::Extension(
      "model.class"          => model_class,
      "model.action"         => action,
      "model.find_by_key"    => find_by_key
    )

    {task: task, id: "model.build", extensions: [injection]}
  end

  class Model
    def call(options, params:,  **)
      builder                 = Model::Builder.new
      options[:model]         = model = builder.call(options, params)
      options["result.model"] = result = Trailblazer::Operation::Result.new(!model.nil?, {})

      result.success?
    end

    class Builder
      def call(options, params)
        action        = options["model.action"] || :new
        model_class   = options["model.class"]
        find_by_key   = options["model.find_by_key"] || :id
        action        = :pass_through unless %i[new find_by].include?(action)

        send("#{action}!", model_class, params, options["model.action"], find_by_key)
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
end
