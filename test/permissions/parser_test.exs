defmodule Piper.Permissions.ParserTest do

  alias Piper.Permissions.Parser
  alias Piper.Permissions.Ast.Rule

  use ExUnit.Case

  defp matches(text, perms, score \\ 0) do
    {:ok, ast, parsed_perms} = Parser.parse(text)
    assert ast.score == score
    json = Parser.rule_to_json!(ast)
    json_ast = Parser.json_to_rule!(json)
    assert json_ast.score == ast.score
    assert "#{ast}" == text
    assert "#{json_ast}" == text
    assert Enum.sort(perms) == parsed_perms
    assert Enum.sort(perms) == Rule.permissions_used(json_ast)
  end

  defp matches_normalized(text, perms, score \\ 0) do
    {:ok, ast, parsed_perms} = Parser.parse(text)
    assert ast.score == score
    json = Parser.rule_to_json!(ast)
    json_ast = Parser.json_to_rule!(json)
    assert json_ast.score == ast.score
    assert "#{ast}" == normalize(text)
    assert "#{json_ast}" == normalize(text)
    assert Enum.sort(perms) == parsed_perms
  end

  # Generates randomized amount of white space
  defp ws() do
    :rand.seed(:exs1024, :os.timestamp())
    String.duplicate(" ", :rand.uniform(7) + 1)
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
    matches "when command is s3:delete with option[bucket] == /work-prod-.*/ must have site:deploy", ["site:deploy"], 1
    matches "when command is s3:delete with arg[0] == 'all' must have site:admin", ["site:admin"], 1
    matches "when command is s3:delete with arg[0] == 'all' and option[bucket] == /work-prod-.*/ must have site:deploy", ["site:deploy"], 2
  end

  test "rules using 'any' input selectors parse" do
    matches "when command is s3:bucket with any arg in [delete, erase] must have site:admin", ["site:admin"], 3
    matches "when command is s3:bucket with any option in [cp, delete] must have site:ops", ["site:ops"], 1
  end

  test "rules using conditional 'any' input selectors parse" do
    matches "when command is s3:bucket with (any arg in [delete, erase]) or any option in [prod, immediate] must have site:management",
      ["site:management"], 4
  end

  test "rules using 'any' permission selectors parse" do
    matches "when command is s3:bucket must have any in [site:ops, s3:read]", ["site:ops", "s3:read"]
    matches "when command is s3:bucket with arg[0] == 'delete' or option[action] == 'delete' must have any in [site:ops, s3:write]",
      ["site:ops", "s3:write"], 2
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

  test "rules using conditional 'all' option selector parse" do
    matches "when command is operable:admin with all option[env] in ['production', 'staging'] must have site:ops", ["site:ops"], 1
  end

  test "namespaced values for args or options parse" do
    matches "when command is operable:admin with option[action] == 'grant' and arg[0] == 'site:deploy' must have site:ops",
      ["site:ops"], 2
    matches "when command is operable:admin with option[action] == 'grant' and option[perm] == 'site:deploy' must have site:ops",
      ["site:ops"], 2
  end

  test "slack emoji commands successfully parse" do
    matches "when command is pd::pager: must have site:ops", ["site:ops"], 0
    matches "when command is pd::pager: with arg[0] == /prod.*/ must have site:ops and site:prod", ["site:ops", "site:prod"], 1
  end

  test "hipchat emoji commands successfully parse" do
    matches "when command is pd:(pager) must have site:ops", ["site:ops"], 0
    matches "when command is pd:(pager) with arg[0] == /prod.*/ must have site:ops and site:prod", ["site:ops", "site:prod"], 1
  end

  test "random whitespacing parses" do
    matches_normalized "when#{ws}command#{ws}is#{ws} s3:bucket must#{ws} have#{ws}all in [s3:read]", ["s3:read"]
    matches_normalized "when#{ws}command#{ws}is#{ws} s3:bucket must#{ws} have#{ws}all in [s3:read]", ["s3:read"]
  end

  test "complicated rule round trips correctly" do
    matches "when command is foo:bar with (option[action] == \"delete\" " <>
      "and arg[0] == /^prod-db/) or (option[action] == \"restart\" " <>
      "and arg[0] == /^prod-lb/) must have foo:write", ["foo:write"], 2
  end

  test "rule returns referenced command name" do
    {:ok, ast, _} = Parser.parse("when command is s3:bucket must have s3:read")
    assert Rule.command_name(ast) == "s3:bucket"
  end

  test "rule returns referenced command even if quoted" do
    {:ok, ast, _} = Parser.parse("when command is \"s3:bucket\" must have s3:read")
    assert Rule.command_name(ast) == "s3:bucket"
  end

  test "parser and lexer error handling" do
    {:error, "illegal characters \"!r\"."} = Parser.parse("when command is foo:bar mst have foo!read")
    {:error, "(Line: 1, Col: 5) syntax error before: \"comand\"."} = Parser.parse("when comand is foo:bar but have foo:read")
    {:error, "(Line: 1, Col: 24) syntax error before: \"foo\"."} = Parser.parse("when command is foo:bar foo:read")
    {:error,
     "(Line: 1, Col: 34) References to permissions must be the literal \"allow\" or start with a command bundle name or \"site\"."} =
      Parser.parse("when command is foo:bar must have foo")
  end

  test "rules allow the keyword 'allow' in permission expressions" do
    matches "when command is s3:bucket allow", []
  end

  test "when 'allow' is used it must be the only phrase in the permission expression" do
    {:error, "(Line: 1, Col: 34) syntax error before: \"allow\"."} = Parser.parse("when command is foo:bar must have allow")
    {:error, "(Line: 1, Col: 46) syntax error before: \"allow\"."} = Parser.parse("when command is foo:bar must have foo:read or allow")
    {:error, "(Line: 1, Col: 30) syntax error before: \"and\"."} = Parser.parse("when command is foo:bar allow and allow")
  end

end
