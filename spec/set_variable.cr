require "../src/spinach"

class SetVariable < SpinachTestCase

  def mapping
    {
      "greeting_for": ->(args : Array(String)){ greeting_for(args) }
    }
  end

  def greeting_for(args)
    username = args.first
    "Hello #{username}, you nancy-boy"
  end
end
