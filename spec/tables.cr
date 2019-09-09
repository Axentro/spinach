require "../src/spinach"

class Tables < SpinachTestCase

  def mapping
    {
      "greeting_for": ->(args : Array(String)){ greeting_for(args) }
    }
  end

  def greeting_for(args)
    firstname = args.first
    lastname = args.last
    {
      "login_greeting" => "Hello #{firstname}!",
      "login_message" => "Your last name is #{lastname}!"
    }
  end

end
