require "../src/spinach"

class AssertEqualsWithVariable < SpinachTestCase

  def mapping
    empty_mapping
  end

  def initialize
   set_variable("username", "Bob")
  end

end
