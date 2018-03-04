module Test
  module Methods
    def find_model(ctx, seq:, **)
      seq << :find_model
    end

    def update(ctx, seq:, **)
      seq << :update
    end

    def notify(ctx, seq:, **)
      seq << :notify
    end

    def rehash(ctx, seq:, rehash_raise:false, **)
      seq << :rehash
      raise if rehash_raise
      true
    end

    def log_error(ctx, seq:, **)
      seq << :log_error
    end
  end
end
