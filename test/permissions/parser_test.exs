defmodule Piper.Permissions.ParserTest do

  alias Piper.Permissions.Parser

  use ExUnit.Case

  defp matches(text, perms) do
    {:ok, ast, parsed_perms} = Parser.parse(text)
    assert "#{ast}" == text
    assert Enum.sort(perms) == parsed_perms
  end

  defp matches_normalized(text, perms) do
    {:ok, ast, parsed_perms} = Parser.parse(text)
    assert "#{ast}" == normalize(text)
    assert Enum.sort(perms) == parsed_perms
  end

  # Generates randomized amount of white space
  defp ws() do
    :random.seed(:os.timestamp())
    String.duplicate(" ", :random.uniform(7) + 1)
  end

  # Normalize more than 1 space character to 1.
  # This function will keep recursively looping until
  # the string stops changing.
  defp normalize(text) do
    text1 = Regex.replace(~r/  /, text, " ", global: true)
    case Regex.replace(~r/( :|: )/, text1, ":", global: true) do
      ^text ->
        text
      text ->
        normalize(text)
    end
  end

  # Force Erlang modules to be reloaded in case tests are being
  # run via mix test.watch
  setup_all do
    for m <- [:piper_rule_lexer, :piper_rule_parser] do
      :code.purge(m)
      :code.delete(m)
      {:module, _} = Code.ensure_compiled(m)
    end
    :ok
  end

  test "minimal rules parse" do
    matches "when command is s3:delete must have s3:write", ["s3:write"]
    matches "when command is s3:delete must have s3:write or site:deploy", ["s3:write", "site:deploy"]
  end

  test "rules with input selector clauses parse" do
    matches "when command is s3:delete with option[bucket] == /work-prod-.*/ must have site:deploy", ["site:deploy"]
    matches "when command is s3:delete with arg[0] == 'all' must have site:admin", ["site:admin"]
    matches "when command is s3:delete with arg[0] == 'all' and option[bucket] == /work-prod-.*/ must have site:deploy", ["site:deploy"]
  end

  test "rules using 'any' input selectors parse" do
    matches "when command is s3:bucket with any arg in [delete, erase] must have site:admin", ["site:admin"]
    matches "when command is s3:bucket with any option in [cp, delete] must have site:ops", ["site:ops"]
  end

  test "rules using conditional 'any' input selectors parse" do
    matches "when command is s3:bucket with (any arg in [delete, erase]) or any option in [prod, immediate] must have site:management",
      ["site:management"]
  end

  test "rules using 'any' permission selectors parse" do
    matches "when command is s3:bucket must have any in [site:ops, s3:read]", ["site:ops", "s3:read"]
    matches "when command is s3:bucket with arg[0] == 'delete' or option[action] == 'delete' must have any in [site:ops, s3:write]",
      ["site:ops", "s3:write"]
  end

  test "rules using conditional 'any' permission selectors parse" do
    matches "when command is s3:bucket must have any in [site:ops, s3:read] or any in [site:management, site:leads] or site:shift_leads and site:ops",
      ["site:management", "site:leads", "site:ops", "s3:read", "site:shift_leads"]
  end

  test "rules using 'all' permission selectors parse" do
    matches "when command is s3:bucket must have all in [s3:read, site:ops]", ["s3:read", "site:ops"]
  end

  test "rules using conditional 'all' permission selectors parse" do
    matches "when command is s3:bucket must have all in [s3:read, site:ops] or all in [site:ops, site:leads]", ["site:ops", "site:leads", "s3:read"]
  end

  test "namespaced values for args or options parse" do
    matches "when command is operable:admin with option[action] == 'grant' and arg[0] == 'site:deploy' must have site:ops",
      ["site:ops"]
    matches "when command is operable:admin with option[action] == 'grant' and option[perm] == 'site:deploy' must have site:ops",
      ["site:ops"]
  end

  test "random whitespacing parses" do
    matches_normalized "when#{ws}command#{ws}is#{ws} s3:bucket must#{ws} have#{ws}all in [s3:read]", ["s3:read"]
    matches_normalized "when#{ws}command#{ws}is#{ws} s3:#{ws}bucket must#{ws} have#{ws}all in [s3#{ws}:read]", ["s3:read"]
  end

  test "complicated rule round trips correctly" do
    matches "when command is foo:bar with (option[action] == \"delete\" " <>
      "and arg[0] == /^prod-db/) or (option[action] == \"restart\" " <>
      "and arg[0] == /^prod-lb/) must have foo:write", ["foo:write"]
  end

end