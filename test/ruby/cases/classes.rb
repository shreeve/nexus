module Geometry
  class Point
    attr_reader :x, :y

    def initialize(x, y)
      @x = x
      @y = y
    end

    def add(other)
      Point.new(@x + other.x, @y + other.y)
    end

    def self.origin
      new(0, 0)
    end
  end
end
