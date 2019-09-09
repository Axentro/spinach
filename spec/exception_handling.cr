require "../src/spinach"

class ExceptionHandling < SpinachTestCase

  def mapping
    {
      "get_greeting":    ->(args : Array(String)){ get_greeting },
    }
  end

  def get_greeting
    raise "Oh no an Exception happened!"
    "must always return a string"
  end

end
