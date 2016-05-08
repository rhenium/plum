# frozen-string-literal: true

using Plum::BinaryString
module Plum
  class Frame::Unknown < Frame
    # Creates a frame with unknown type value.
    def initialize(type_value, **args)
      initialize_base(type_value: type_value, **args)
    end
  end
end

