defmodule Bind.BindTest do

  use ExUnit.Case

  alias Piper.Command.Parser
  alias Piper.Command.ParserOptions
  alias Piper.Command.Bindable
  alias Piper.Command.Bind
  alias Piper.Command.Ast, as: Ast

  defp link_scopes([]) do
    Bind.Scope.empty_scope()
  end
  defp link_scopes(vars) do
    make_scope_chain(Enum.reverse(vars))
  end

  defp make_scope_chain([h]) do
    Bind.Scope.from_map(h)
  end
  defp make_scope_chain([h|t]) do
    parent = make_scope_chain(t)
    scope = Bind.Scope.from_map(h)
    {:ok, scope} = Piper.Command.Scoped.set_parent(scope, parent)
    scope
  end

  defp parse_and_bind(text) do
    parse_and_bind(text, Bind.Scope.empty_scope())
  end

  defp parse_and_bind(text, vars) when is_map(vars) do
    scope = Bind.Scope.from_map(vars)
    parse_and_bind2(text, scope)
  end
  defp parse_and_bind2(text, scope, opts \\ %ParserOptions{}) do
    {:ok, ast} = Parser.scan_and_parse(text, opts)
    {:ok, scope} = Bindable.resolve(ast, scope)
    {:ok, new_ast, _scope} = Bindable.bind(ast, scope)
    {:ok, new_ast}
  end

  defp arg(%Ast.Pipeline{}=ast, index) do
    Enum.at(ast.stages.left.args, index)
  end

  test "preparing simple command" do
    {:ok, ast} = parse_and_bind("echo 'foo'")
    assert "#{ast.stages.left.name}" == "echo"
    assert arg(ast, 0) == "foo"
    assert "#{ast}" == "echo foo"
  end

  test "preparing command with options" do
    {:ok, ast} = parse_and_bind("ec2:list_vms --region=us-east-1")
    assert "#{ast.stages.left.name}" == "ec2:list_vms"
    assert "#{arg(ast, 0).name}" == "region"
    assert "#{arg(ast, 0).value}" == "us-east-1"
    assert "#{ast}" == "ec2:list_vms --region=us-east-1"
  end

  test "preparing command with variable arg" do
    {:ok, ast} = parse_and_bind("ec2:list_vms --region=$region", %{"region" => "us-west-1"})
    assert "#{ast.stages.left.name}" == "ec2:list_vms"
    assert "#{arg(ast, 0).name}" == "region"
    assert "#{arg(ast, 0).value}" == "us-west-1"
    assert "#{ast}" == "ec2:list_vms --region=us-west-1"
  end

  test "preparing command with the same variable multiple times" do
    {:ok, ast} = parse_and_bind("echo $padding $value $padding", %{"padding" => "***", "value" => "cheeseburger"})
    assert "#{ast}" == "echo *** cheeseburger ***"
  end

  test "preparing command with chained scopes" do
    scope_chain = link_scopes([%{"user" => "becky"}, %{"region" => "us-west-2"}, %{"page_count" => 5}])
    {:ok, ast} = parse_and_bind2("ec2:list_vms --region=$region --user=$user $page_count", scope_chain)
    assert "#{ast}" == "ec2:list_vms --region=us-west-2 --user=becky 5"
  end

  test "array indexing" do
    scope = Bind.Scope.from_map(%{"region" => ["us-west-1", "us-east-1"]})
    {:ok, ast} = parse_and_bind2("ec2:list_vms --region=$region[1]", scope)
    assert "#{ast}" == "ec2:list_vms --region=us-east-1"
  end

  test "map indexing" do
    scope = Bind.Scope.from_map(%{"envs" => %{"prod" => "us-east-1", "test" => "us-west-2"}})
    {:ok, ast} = parse_and_bind2("ec2:list_vms --region=$envs.prod", scope)
    assert "#{ast}" == "ec2:list_vms --region=us-east-1"
  end

  test "nested access" do
    envs = [%{"region" => "us-east-1", "owner" => "admin1"}, %{"region" => "us-west-2", "owner" => "admin2"}]
    scope = Bind.Scope.from_map(%{"envs" => envs})
    {:ok, ast} = parse_and_bind2("site:monkey_with_vms --region=$envs[0].region --notify=$envs[0].owner", scope)
    assert "#{ast}" == "site:monkey_with_vms --region=us-east-1 --notify=admin1"
  end

  test "moar nested access" do
    envs = [%{"region" => "us-east-1", "owners" => ["admin1", "admin3"]}, %{"region" => "us-west-2", "owners" => ["admin2"]}]
    scope = Bind.Scope.from_map(%{"envs" => envs})
    {:ok, ast} = parse_and_bind2("site:monkey_with_vms --region=$envs[0].region --notify=$envs[0].owners[1]", scope)
    assert "#{ast}" == "site:monkey_with_vms --region=us-east-1 --notify=admin3"
  end

  test "nested access with spaces in keys" do
    envs = [%{"region" => "us-east-1", "env owners" => ["admin1", "admin3"]}, %{"region" => "us-west-2", "owner" => "admin2"}]
    scope = Bind.Scope.from_map(%{"envs" => envs})
    {:ok, ast} = parse_and_bind2("site:monkey_with_vms --region=$envs[0].region --notify=$envs[0].'env owners'[1]", scope)
    assert "#{ast}" == "site:monkey_with_vms --region=us-east-1 --notify=admin3"
  end

  test "old school map access" do
    envs = [%{"region" => "us-east-1", "env owners" => ["admin1", "admin3"]}, %{"region" => "us-west-2", "owner" => "admin2"}]
    scope = Bind.Scope.from_map(%{"envs" => envs})
    {:ok, ast} = parse_and_bind2("site:monkey_with_vms --region=$envs[0][region] --notify=$envs[0]['env owners'][1]", scope)
    assert "#{ast}" == "site:monkey_with_vms --region=us-east-1 --notify=admin3"
  end

  # TODO: Add back support for indexed variables
  # test "array indexing" do
  #   scope = Bind.Scope.from_map(%{"region" => ["us-west-1", "us-east-1"]})
  #   {:ok, ast} = parse_and_bind2("ec2:list_vms --region=$region[1]", scope)
  #   assert "#{ast}" == "ec2:list_vms --region=us-east-1"
  # end

  # TODO: Add back support for indexed variables
  # test "map indexing" do
  #   scope = Bind.Scope.from_map(%{"region" => %{"west-1" => "us-west-1", "east" => "us-east-1"}})
  #   {:ok, ast} = parse_and_bind2("ec2:list_vms --region=$region[\"west-1\"]", scope)
  #   assert "#{ast}" == "ec2:list_vms --region=us-west-1"
  # end

end
