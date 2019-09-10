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
  getter implementation_status : String
  getter trace : Array(String)?

  def initialize(@expected : String, @actual : String | Hash(String, String), @passed : Bool, @implementation_status : String, @trace : Array(String)?)
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
    parser = prepare_table_scenarios(parser)
    execute_scenarios(node_type, filename, parser, template_path)
  end

  def prepare_table_scenarios(parser)
    parser.root!.scope.select { |n| n.attributes.keys.includes?("spinach:table_scenario") }.each_with_index do |node, index|
      node.attribute_remove("spinach:table_scenario")

      command_map = {} of String => Hash(String, String)
      node.scope.select { |n| n.tag_name == "th" }.each_with_index do |th, x|
        th.attributes.select { |k, v| k.starts_with?("spinach") }.each { |k, v| th.attribute_remove(k); command_map["#{index}_td_#{x}"] = {k => v} }
      end

      node.scope.select { |n| n.tag_name == "tr" }.to_a[1..-1].each_with_index do |tr, i|
        tr.attribute_add("spinach:scenario", "table scenario #{index}-#{i}")
        tr.scope.select { |n| n.tag_name == "td" }.each_with_index do |td, x|
          if kv = command_map["#{index}_td_#{x}"]?
            td.attribute_add(kv.first_key, kv.first_value)
          end
        end
      end
    end

    parser
  end

  def execute_scenarios(node_type, filename, parser, template_path)
    results = parser.root!.scope.select { |n| n.attributes.keys.includes?("spinach:scenario") }.flat_map do |node|
      scenario_name = node.attributes["spinach:scenario"]
      implementation_status = node.attributes["spinach:status"]? || "expected_to_pass"
      commands = locate_commands(node)
      execute_commands(commands, node_type, parser, filename, scenario_name, implementation_status, template_path)
    end.to_a

    generate_cli_reports(results)
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

      implementation_status = node.attributes["spinach:status"]?
      value = node.attributes["spinach:assert_equals"]
      kind = kind_of_assert(value)
      case kind
      when AssertKind::METHOD
        res = process_command(value)
        AssertEqualsCommand.new(res[:method], node.inner_text, implementation_status, res[:args])
      else
        AssertEqualsVariableCommand.new(value, node.inner_text, implementation_status)
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

  def execute_commands(commands, node_type, parser, filename, scenario_name, implementation_status, template_path)
    report_data = [] of ReportData
    klass = node_type.new
    commands.each do |command|
      case command
      when SetVariableCommand
        klass.set_variable(command.name, command.value)
      when AssertEqualsVariableCommand
        expected = command.value
        status = command.implementation_status || implementation_status

        if is_execution_variable?(command.variable_name)
          if status == "pending" || status == "ignored"
            report_data << ReportData.new(expected, "", true, status, nil)
          else
            data = execution_data(command.variable_name)
            result_map = klass.get_variable(data[:variable_name])
            actual = result_map[data[:method]]
            result = actual == expected
            report_data << ReportData.new(expected, actual, result, status, nil)
          end
        else
          if status == "pending" || status == "ignored"
            report_data << ReportData.new(expected, "", true, status, nil)
          else
            actual = klass.get_string_variable(command.variable_name)
            result = actual == expected
            report_data << ReportData.new(expected, actual, result, status, nil)
          end
        end
      when ExecuteCommand
        args = command.args.map { |arg| klass.get_string_variable(arg) }
        result_map = klass.mapping[command.method].call(args)
        klass.set_variable(command.variable_name, result_map)
      when AssertEqualsCommand
        expected = command.value
        status = command.implementation_status || implementation_status
        if status == "pending" || status == "ignored"
          report_data << ReportData.new(expected, "", true, status, nil)
        else
          begin
            args = command.args.map { |arg| klass.get_string_variable(arg) }
            actual = klass.mapping[command.method].call(args)
            result = actual == expected
            report_data << ReportData.new(expected, actual, result, status, nil)
          rescue e : Exception
            report_data << ReportData.new(expected, e.to_s, false, status, e.backtrace?)
          end
        end
      end
    end
    {report_data: report_data, scenario_name: scenario_name, filename: filename}
  end

  def generate_cli_reports(results)
    results.flat_map { |res| res[:report_data] }.each do |r|
      output = if r.implementation_status == "pending"
                 "P".colorize(:blue)
               elsif r.implementation_status == "ignored"
                 "I".colorize(:yellow)
               else
                 if r.passed && r.implementation_status == "expected_to_fail"
                   "F".colorize(:red)
                 elsif r.passed && r.implementation_status == "expected_to_pass"
                   ".".colorize(:green)
                 else
                   if r.implementation_status == "expected_to_fail"
                     "F".colorize(:green)
                   else
                     "F".colorize(:red)
                   end
                 end
               end
      print output
    end
  end

  def generate_html_reports(results, filename, parser, template_path)
    report_path = "#{__DIR__}/../../../#{template_path}/reports"
    FileUtils.mkdir_p(report_path) unless File.exists?(report_path)
    target_out = "#{report_path}/#{filename}.report.html"

    results.each do |result_set|
      parser.root!.scope.each do |node|
        if node.attributes.keys.includes?("spinach:scenario") && node.attributes["spinach:scenario"] == result_set[:scenario_name]
          report_data = result_set[:report_data]

          assert_equals_count = 0
          node.scope.each do |scenario_node|
            classes = scenario_node.tag_name == "td" ? "" : "bg-light p-1"
            if scenario_node.attributes.keys.includes?("spinach:assert_equals")
              result = report_data[assert_equals_count]

              if result.implementation_status == "pending"
                badge = create_badge(parser, result.implementation_status, "info")
                scenario_node.append_child(badge)
              elsif result.implementation_status == "ignored"
                badge = create_badge(parser, result.implementation_status, "secondary")
                scenario_node.append_child(badge)
              else
                if result.passed
                  scenario_node.attribute_add("class", "text-success #{classes}")
                  if result.implementation_status == "expected_to_fail"
                    badge = create_badge(parser, result.implementation_status, "danger")
                    scenario_node.append_child(badge)
                  end
                else
                  scenario_node.attribute_add("class", "text-danger #{classes}")

                  failure = parser.tree.create_node(:span)
                  failure.attribute_add("class", "text-muted #{classes}")
                  failure.inner_text = " | #{result.actual}"
                  scenario_node.append_child(failure)

                  if result.implementation_status == "expected_to_fail"
                    badge = create_badge(parser, result.implementation_status, "success")
                    scenario_node.append_child(badge)
                  end

                  if trace = result.trace
                    alert = create_alert(parser, trace.join("\n"))
                    scenario_node.append_child(alert)
                  end
                end
              end

              assert_equals_count += 1
            end
          end
        end
      end
      File.open(target_out, "w") { |f|
        f.puts parser.to_html
      }
    end
  end

  private def create_badge(parser, text, kind)
    badge = parser.tree.create_node(:span)
    badge.attribute_add("class", "badge badge-#{kind} ml-1 p-1")
    badge.inner_text = text
    badge
  end

  private def create_alert(parser, text)
    alert = parser.tree.create_node(:div)
    alert.attribute_add("class", "alert alert-danger mt-2")
    alert.attribute_add("role", "alert")
    alert.inner_text = text
    alert
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
    has_failures = res[:report_data].reject(&.passed).reject { |r| r.implementation_status == "expected_to_fail" }.size > 0
    has_incorrect_passes = res[:report_data].select { |r| r.passed && r.implementation_status == "expected_to_fail" }.size > 0
    if has_failures || has_incorrect_passes
      filename = res[:filename]
      puts ""
      puts ""
      puts "#{filename}.cr".colorize(:magenta).to_s + " : " + "#{res[:scenario_name]}".colorize(:blue).to_s
      res[:report_data].reject { |r| (r.passed && r.implementation_status == "expected_to_pass") ||
        r.implementation_status == "pending" ||
        r.implementation_status == "ignored" ||
        !r.passed && r.implementation_status == "expected_to_fail" }.each do |data|
        puts "expected: #{data.expected}".colorize(:red)
        puts "  actual: #{data.actual}".colorize(:red)
      end
    end
  end
  num_passed = results.flat_map { |r| r[:report_data] }.select { |r| r.passed && r.implementation_status == "expected_to_pass" }.size
  num_ignored = results.flat_map { |r| r[:report_data] }.select { |r| r.implementation_status == "ignored" }.size
  num_pending = results.flat_map { |r| r[:report_data] }.select { |r| r.implementation_status == "pending" }.size
  num_failed = results.flat_map { |r| r[:report_data] }.select { |r| !r.passed && r.implementation_status != "expected_to_fail" }.size
  num_expected_failed = results.flat_map { |r| r[:report_data] }.select { |r| !r.passed && r.implementation_status == "expected_to_fail" }.size
  num_passed_incorrectly = results.flat_map { |r| r[:report_data] }.select { |r| r.passed && r.implementation_status == "expected_to_fail" }.size
  total_failed = num_failed + num_passed_incorrectly
  total = num_passed + num_ignored + num_pending + num_failed + num_expected_failed + num_passed_incorrectly
  summary = "Passed: #{num_passed + num_expected_failed}, Failed: #{total_failed}, Ignored: #{num_ignored}, Pending: #{num_pending}, Total: #{total}"
  puts ""
  puts ""
  puts (total_failed > 0 ? summary.colorize(:red) : summary.colorize(:green))
  puts ""
  exit total_failed
end

results = all_test_cases.map do |test|
  test.new.run(test, location)
end

test_summary(results)
