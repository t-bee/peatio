module Seed
  class Base
    def initialize(settings)
      @settings = settings
    end

    def prefetch_currencies
    end

    def base_currency
      @base_currency ||= @settings[:base_currency]
    end

    def output_file
      @output_file = Rails.root.join("config/seed-v2/#{@settings[:seed_filename]}")
    end
  end
end
