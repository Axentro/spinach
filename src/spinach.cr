require "option_parser"
require "myhtml"
require "file_utils"
require "colorize"
require "./commands"

location : String = "spec"

OptionParser.parse! do |parser|
  parser.banner = "Usage: spinach [arguments]"
  parser.on("-l LOCATION", "--location=LOCATION", "Location of specs (defaults to specs dir)") do |loc|
    location = loc
  end
end

enum AssertKind
  METHOD
  VARIABLE
end

class ReportData
  getter expected : String
  getter actual : String | Hash(String, String)
  getter passed : Bool

  def initialize(@expected : String, @actual : String | Hash(String, String), @passed : Bool)
  end
end

alias Command = AssertEqualsCommand | AssertEqualsVariableCommand | SetVariableCommand | ExecuteCommand

class Scenario
  getter name : String
  getter commands : Array(Command)

  def initialize(@name : String, @commands : Array(Command)); end
end

alias VariableValue = Hash(String, String)
alias Variables = Hash(String, VariableValue)

abstract class SpinachTestCase
  abstract def mapping : Hash(String, Proc)

  # -- variables --
  @variables : Variables = {} of String => VariableValue

  def set_variable(variable_name : String, value : String)
    @variables[variable_name] = {"value" => value}
  end

  def set_variable(variable_name : String, value : VariableValue)
    @variables[variable_name] = value
  end

  def get_string_variable(variable_name : String) : String
    @variables[variable_name]? ? @variables[variable_name]["value"] : variable_name
  end

  def get_variable(variable_name : String) : VariableValue
    @variables[variable_name]? ? @variables[variable_name] : {"value" => variable_name}
  end

  def variables
    @variables
  end

  def clear_variables
    @variables = {} of String => VariableValue
  end

  def empty_mapping
    {"none": ->(args : Array(String)) { "" }}
  end

  def run(node_type, template_path)
    filename = node_type.to_s.underscore
    template = "#{__DIR__}/../../../#{template_path}/#{filename}.html"
    parser = Myhtml::Parser.new(File.read(template))
    execute_scenarios(node_type, filename, parser, template_path)
  end

  def execute_scenarios(node_type, filename, parser, template_path)
    results = parser.root!.scope.select { |n| n.attributes.keys.includes?("spinach:scenario") }.flat_map do |node|
      scenario_name = node.attributes["spinach:scenario"]
      commands = locate_commands(node)
      execute_commands(commands, node_type, parser, filename, scenario_name, template_path)
    end.to_a

    generate_cli_reports(results, filename)
    generate_html_reports(results, filename, parser, template_path)
    {results: results, filename: filename}
  end

  def locate_commands(node)
    locate_set_variable_commands(node) +
      locate_execute_commands(node) +
      locate_assert_equals_commands(node)
  end

  private def locate_assert_equals_commands(node)
    node.scope.select { |n| n.attributes.keys.includes?("spinach:assert_equals") }.map do |node|
      other_attrs = node.attributes.keys.reject { |attr| attr.starts_with?("spinach") }
      raise "Error: the node for spinach:assert_equals must not contain any non spinach attributes - please remove these: #{other_attrs}" if other_attrs.size > 0

      value = node.attributes["spinach:assert_equals"]
      kind = kind_of_assert(value)
      case kind
      when AssertKind::METHOD
        res = process_command(value)
        AssertEqualsCommand.new(res[:method], node.inner_text, res[:args])
      else
        AssertEqualsVariableCommand.new(value, node.inner_text)
      end
    end.to_a
  end

  private def kind_of_assert(value) : AssertKind
    if value.split("(").size > 1
      AssertKind::METHOD
    else
      AssertKind::VARIABLE
    end
  end

  private def locate_set_variable_commands(node)
    node.scope.select { |n| n.attributes.keys.includes?("spinach:set") }.map do |node|
      variable_name = node.attributes["spinach:set"]
      SetVariableCommand.new(variable_name, node.inner_text)
    end.to_a
  end

  private def locate_execute_commands(node)
    node.scope.select { |n| n.attributes.keys.includes?("spinach:execute") }.map do |node|
      res = process_execute_command(node.attributes["spinach:execute"])
      ExecuteCommand.new(res[:method], res[:variable_name], res[:args])
    end.to_a
  end

  private def process_execute_command(command)
    data = command.split("=")
    variable_name = data.first.strip
    method = data.last.reverse.strip.reverse
    base = process_command(method)
    {variable_name: variable_name, method: base[:method], args: base[:args]}
  end

  private def process_command(command)
    data = command.split("(")
    base_command = data.first
    args = data.last.split(",").map { |arg| arg.gsub(")", "").reverse.strip.reverse.strip }
    {method: base_command, args: args}
  end

  private def is_execution_variable?(value)
    value.split(".").size > 1
  end

  private def execution_data(value)
    data = value.split(".")
    {variable_name: data.first, method: data.last}
  end

  def execute_commands(commands, node_type, parser, filename, scenario_name, template_path)
    report_data = [] of ReportData
    klass = node_type.new
    commands.each do |command|
      case command
      when SetVariableCommand
        klass.set_variable(command.name, command.value)
      when AssertEqualsVariableCommand
        expected = command.value

        if is_execution_variable?(command.variable_name)
          data = execution_data(command.variable_name)
          result_map = klass.get_variable(data[:variable_name])
          actual = result_map[data[:method]]
          result = actual == expected
          report_data << ReportData.new(expected, actual, result)
        else
          actual = klass.get_string_variable(command.variable_name)
          result = actual == expected
          report_data << ReportData.new(expected, actual, result)
        end
      when ExecuteCommand
        args = command.args.map { |arg| klass.get_string_variable(arg) }
        result_map = klass.mapping[command.method].call(args)
        klass.set_variable(command.variable_name, result_map)
      when AssertEqualsCommand
        args = command.args.map { |arg| klass.get_string_variable(arg) }

        actual = klass.mapping[command.method].call(args)
        expected = command.value
        result = actual == expected
        report_data << ReportData.new(expected, actual, result)
      end
    end
    # generate_cli_reports(report_data, name)
    # generate_html_reports(report_data, name, parser, template_path)
    {report_data: report_data, scenario_name: scenario_name, filename: filename}
  end

  def generate_cli_reports(results, name)
    results.flat_map { |res| res[:report_data] }.each do |r|
      print (r.passed ? ".".colorize(:green) : "F".colorize(:red))
    end
  end

  def generate_html_reports(results, filename, parser, template_path)
    report_path = "#{__DIR__}/../../../#{template_path}/reports"
    FileUtils.mkdir_p(report_path) unless File.exists?(report_path)
    target_out = "#{report_path}/#{filename}.report.html"

    report_data = results.flat_map { |res| res[:report_data] }.to_a

    assert_equals_count = 0
    parser.root!.scope.each do |node|
      if node.attributes.keys.includes?("spinach:assert_equals")
        result = report_data[assert_equals_count]

        if result.passed
          node.attribute_add("class", "text-success bg-light p-1")
        else
          node.attribute_add("class", "text-danger bg-light p-1")

          failure = parser.tree.create_node(:span)
          failure.attribute_add("class", "text-muted bg-light p-1")
          failure.inner_text = " | #{result.actual}"
          node.append_child(failure)
        end

        assert_equals_count += 1
      end
      node
    end

    File.open(target_out, "w") { |f|
      f.puts parser.to_html
    }
  end
end

def all_test_cases
  {% begin %}
    {{SpinachTestCase.all_subclasses}}
  {% end %}
end

def test_summary(data)
  results = data.flat_map { |d| d[:results] }
  results.each do |res|
    has_failures = res[:report_data].reject(&.passed).size > 0
    if has_failures
      filename = res[:filename]
      puts ""
      puts ""
      puts "#{filename}.cr".colorize(:magenta).to_s + " : " + "#{res[:scenario_name]}".colorize(:blue).to_s
      res[:report_data].reject(&.passed).each do |data|
        puts "expected: #{data.expected}".colorize(:red)
        puts "  actual: #{data.actual}".colorize(:red)
      end
    end
  end
  num_passed = results.flat_map { |r| r[:report_data] }.select { |r| r.passed }.size
  num_failed = results.flat_map { |r| r[:report_data] }.select { |r| !r.passed }.size
  summary = "Passed: #{num_passed}, Failed: #{num_failed}, Total: #{num_passed + num_failed}"
  puts ""
  puts ""
  puts (num_failed > 0 ? summary.colorize(:red) : summary.colorize(:green))
  puts ""
  exit num_failed
end

results = all_test_cases.map do |test|
  test.new.run(test, location)
end

test_summary(results)
