require "../src/spinach"

class ExceptionHandling < SpinachTestCase

  @[Spinach]
  def get_greeting(args)
    raise "Oh no an Exception happened!"
    "must always return a string"
  end

end
