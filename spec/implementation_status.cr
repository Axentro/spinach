require "../src/spinach"

class ImplementationStatus < SpinachTestCase

  @[Spinach]
  def get_greeting(args)
    "Hello World!"
  end

  @[Spinach]
  def failed_greeting(args)
    "Boo!"
  end

end
