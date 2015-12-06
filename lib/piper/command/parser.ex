defmodule Piper.Command.Parser do

  alias Piper.Command.Ast
  alias Piper.Command.SyntaxError
  alias Piper.Util.Token

  defstruct [tokens: nil, nodes: []]

  def scan_and_parse(text) when is_binary(text) do
    case Piper.Command.Lexer.tokenize(text) do
      {:ok, tokens} ->
        parse(tokens)
      error ->
        Piper.Command.Lexer.format_error(error)
    end
  end

  def parse(tokens) when is_list(tokens) do
    case parse_invocation(%__MODULE__{tokens: tokens}) do
      %SyntaxError{}=error ->
        SyntaxError.format_error(error)
      parser ->
        {_parser, result} = pop_node(parser)
        {:ok, result}
    end
  end

  defp parse_pipeline(parser) do
    case pop_token(parser) do
      {parser, %Token{type: type}=token} when type in [:pipe, :iff] ->
        {parser, pipeline} = case pop_node(parser) do
                               {parser, %Ast.Invocation{}=invocation} ->
                                 pipeline = Ast.Pipeline.new(token)
                                 {parser, Ast.Pipeline.add_invocation(pipeline, invocation)}
                               {parser, %Ast.Pipeline{type: ^type}=pipeline} ->
                                 {parser, pipeline}
                               {parser, node} ->
                                 {push_node(parser, node), Ast.Pipeline.new(token)}
                             end
        case parse_invocation(pop_token(parser)) do
          %SyntaxError{}=error ->
            error
          parser ->
            {parser, invocation} = pop_node(parser)
            pipeline = Ast.Pipeline.add_invocation(pipeline, invocation)
            parser = push_node(parser, pipeline)
            case more_tokens?(parser) do
              false ->
                assemble_pipelines(parser)
              true ->
                parse_pipeline(parser)
            end
        end
      {parser, token} ->
        parser = assemble_pipelines(parser)
        push_token(parser, token)
    end
  end

  defp assemble_pipelines({parser, %Ast.Pipeline{}=pipeline}) do
    assemble_pipelines(pop_node(parser), pipeline)
  end
  defp assemble_pipelines({parser, node}) do
    push_node(parser, node)
  end
  defp assemble_pipelines(parser) do
    assemble_pipelines(pop_node(parser))
  end

  defp assemble_pipelines({parser, %Ast.Pipeline{}=first}, next) do
    first = Ast.Pipeline.add_pipeline(first, next)
    assemble_pipelines(push_node(parser, first))
  end
  defp assemble_pipelines({parser, node}, next) do
    parser = push_node(parser, node)
    push_node(parser, next)
  end

  defp parse_invocation({parser, %Token{type: :string}=token}) do
    case pop_token(parser) do
      {parser, %Token{type: :colon}} ->
        case pop_token(parser) do
          {parser, %Token{type: :string}=token1} ->
            combined = %Token{line: token.line, col: token.col, type: :string,
                              text: token.text <> ":" <> token1.text}
            push_node(parser, Ast.Invocation.new(combined))
            |> parse_args
          {_parser, errtoken} ->
            SyntaxError.new(:invocation, :command_name, errtoken)
        end
      {parser, tok} ->
        push_token(parser, tok)
        |> push_node(Ast.Invocation.new(token))
        |> parse_args
    end
  end
  defp parse_invocation({parser, %Token{type: :variable}=token}) do
    case parse_variable({parser, token}) do
      {parser, true} ->
        {parser, var} = pop_node(parser)
        push_node(parser, Ast.Invocation.new(var))
        |> parse_args
      error ->
        error
    end
  end
  defp parse_invocation({_parser, token}) do
    SyntaxError.new(:invocation, :command_name, token)
  end
  defp parse_invocation(%__MODULE__{}=parser) do
    case parse_invocation(pop_token(parser)) do
      %SyntaxError{}=error ->
        error
      parser ->
        parse_pipeline(parser)
    end
  end

  defp parse_args({parser, %Token{type: :option}=token}) do
    case pop_token(parser) do
      {parser, %Token{type: :variable}=tok} ->
        option = Ast.Option.new(Ast.Variable.new(tok))
        case parse_option_value(parser, option) do
          {parser, %Ast.Option{}=option} ->
            {parser, invocation} = pop_node(parser)
            invocation = Ast.Invocation.add_arg(invocation, option)
            parser = push_node(parser, invocation)
            parse_args(pop_token(parser))
          %SyntaxError{}=error ->
            error
        end
      {parser, %Token{type: type}=tok} when type in [:string, :integer] ->
        option = Ast.Option.new(tok)
        case parse_option_value(parser, option) do
          {parser, %Ast.Option{}=option} ->
            {parser, invocation} = pop_node(parser)
            invocation = Ast.Invocation.add_arg(invocation, option)
            parser = push_node(parser, invocation)
            parse_args(pop_token(parser))
          %SyntaxError{}=error ->
            error
        end
      {_parser, _token} ->
        SyntaxError.new(:option, [:variable, :string, :integer], token)
    end
  end
  defp parse_args({parser, token}) do
    case parse_value({parser, token}) do
      {parser, true} ->
        {parser, arg} = pop_node(parser)
        {parser, invocation} = pop_node(parser)
        invocation = Ast.Invocation.add_arg(invocation, arg)
        parser = push_node(parser, invocation)
        parse_args(pop_token(parser))
      {parser, false} ->
        parser
    end
  end
  defp parse_args(parser) do
    parse_args(pop_token(parser))
  end

  defp parse_option_value(parser, option) do
    case pop_token(parser) do
      {parser, %Token{type: :equals}} ->
        case parse_value(pop_token(parser)) do
          {parser, true} ->
            {parser, value} = pop_node(parser)
            {parser, Ast.Option.set_value(option, value)}
          {parser, false} ->
            {_, token} = pop_token(parser)
            SyntaxError.new(:invocation, [:integer, :float, :string, :variable], token)
        end
      _ ->
        {parser, option}
    end
  end

  defp parse_value({parser, %Token{type: :integer}=token}) do
    {push_node(parser, Ast.Integer.new(token)), true}
  end
  defp parse_value({parser, %Token{type: :float}=token}) do
    {push_node(parser, Ast.Float.new(token)), true}
  end
  defp parse_value({parser, %Token{type: :bool}=token}) do
    {push_node(parser, Ast.Bool.new(token)), true}
  end
  defp parse_value({parser, %Token{type: :json}=token}) do
    {push_node(parser, Ast.Json.new(token)), true}
  end
  defp parse_value({parser, %Token{type: token_type}=token}) when token_type in [:quoted_string, :string] do
    case pop_token(parser) do
      {parser, %Token{type: :colon}=ctok} ->
        {parser, tok1} = pop_token(parser)
        if tok1 == nil do
          {push_token(parser, ctok), false}
        else
          # Synthesize a new token combining the text of all three
          # and treat it as a string
          new_token = %Token{line: token.line, col: token.col,
                             text: token.text <> ":" <> tok1.text}
          {push_node(parser, Ast.String.new(new_token)), true}
        end
      {parser, tok} ->
        parser = push_token(parser, tok)
        {push_node(parser, Ast.String.new(%{token | type: :string})), true}
    end
  end
  defp parse_value({parser, %Token{type: :variable}=token}) do
    parse_variable({parser, token})
  end
  defp parse_value({parser, token}) do
    {push_token(parser, token), false}
  end

  def parse_variable({parser, %Token{type: type}=token}) when type in [:variable, :optvar] do
    case pop_token(parser) do
      {parser, %Token{type: :lbracket}} ->
        case parse_value(pop_token(parser)) do
          {parser, true} ->
            case pop_token(parser) do
              {parser, %Token{type: :rbracket}} ->
                {parser, index} = pop_node(parser)
                var = Ast.Variable.new(token)
                {push_node(parser, Ast.Variable.set_index(var, index)), true}
              _ ->
                {parser, false}
            end
          {_, false} ->
            {parser, false}
        end
      _ ->
        {push_node(parser, Ast.Variable.new(token)), true}
    end
  end

  # Token stack helpers
  defp pop_token(%__MODULE__{tokens: []}=parser) do
    {parser, nil}
  end
  defp pop_token(%__MODULE__{tokens: [h|t]}=parser) do
    {%{parser | tokens: t}, h}
  end

  defp push_token(parser, nil) do
    parser
  end
  defp push_token(%__MODULE__{tokens: tokens}=parser, token) do
    %{parser | tokens: [token|tokens]}
  end

  defp more_tokens?(%__MODULE__{tokens: []}) do
    false
  end
  defp more_tokens?(%__MODULE__{}) do
    true
  end

  # Node stack helpers
  defp push_node(%__MODULE__{nodes: nodes}=parser, node) do
    %{parser | nodes: [node | nodes]}
  end

  defp pop_node(%__MODULE__{nodes: []}=parser) do
    {parser, nil}
  end
  defp pop_node(%__MODULE__{nodes: [h|t]}=parser) do
    {%{parser | nodes: t}, h}
  end

end