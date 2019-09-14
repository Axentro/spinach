require "../src/spinach"

class ExecuteFunction < SpinachTestCase

  @[Spinach]
  def greeting_for(args)
    firstname = args.first
    lastname = args.last
    {
      "login_greeting" => "Hello #{firstname}!",
      "login_message" => "Your last name is #{lastname}!"
    }
  end

end
