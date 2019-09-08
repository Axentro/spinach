require "../src/spinach"

class ImplementationStatus < SpinachTestCase

  def mapping
    {
      "get_greeting": ->(args : Array(String)){ get_greeting },
      "failed_greeting": ->(args : Array(String)){ failed_greeting }
    }
  end

  def get_greeting
    "Hello World!"
  end

  def failed_greeting
    "Boo!"
  end

end
