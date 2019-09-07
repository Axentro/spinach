class AssertEqualsCommand
  getter method : String
  getter args : Array(String)
  getter value : String

  def initialize(@method : String, @value : String, @args : Array(String) = [] of String)
  end

  def has_args?
    args.size > 0
  end
end

class AssertEqualsVariableCommand
  getter variable_name : String
  getter value : String

  def initialize(@variable_name : String, @value : String)
  end
end

class SetVariableCommand
  getter name : String
  getter value : String

  def initialize(@name : String, @value : String)
  end
end

class ExecuteCommand
  getter method : String
  getter args : Array(String)
  getter variable_name : String

  def initialize(@method : String, @variable_name : String, @args : Array(String) = [] of String)
  end

  def has_args?
    args.size > 0
  end
end
