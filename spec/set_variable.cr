require "../src/spinach"

class SetVariable < SpinachTestCase

  @[Spinach]
  def greeting_for(args)
    username = args.first
    "Hello #{username}, you nancy-boy"
  end

end
