require "../src/spinach"

class AssertEqualsWithVariable < SpinachTestCase

  def initialize
   set_variable("username", "Bob")
  end

end
