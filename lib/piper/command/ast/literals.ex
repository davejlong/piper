defmodule Piper.Command.Ast.Integer do

  defstruct [line: nil, col: nil, value: nil]

  def new({:integer, {line, col}, value}) do
    %__MODULE__{line: line, col: col, value: String.to_integer(String.Chars.to_string(value))}
  end
  def new({:integer, _, value}) do
    new({:integer, {0, 0}, value})
  end

end

defmodule Piper.Command.Ast.Float do

  defstruct [line: nil, col: nil, value: nil]

  def new({:float, {line, col}, value}) do
    %__MODULE__{line: line, col: col, value: String.to_float(String.Chars.to_string(value))}
  end
  def new({:float, _, value}) do
    new({:float, {0, 0}, value})
  end

end

defmodule Piper.Command.Ast.Bool do

  defstruct [line: nil, col: nil, value: nil]

  def new({:bool, {line, col}, value}) do
    %__MODULE__{line: line, col: col, value: convert(value)}
  end
  def new({:bool, _, value}) do
    new({:bool, {0, 0}, value})
  end

  def new(line, col, value) do
    new({:bool, {line, col}, value})
  end

  defp convert('true') do
    true
  end
  defp convert('false') do
    false
  end

end

defmodule Piper.Command.Ast.String do

  defstruct [line: nil, col: nil, value: nil, quote_type: nil]

  def new({:string, {line, col}, value}) do
    %__MODULE__{line: line, col: col, value: String.Chars.to_string(value)}
  end
  def new({:datum, {line, col}, value}) do
    %__MODULE__{line: line, col: col, value: String.Chars.to_string(value)}
  end
  def new({:emoji, {line, col}, value}) do
    %__MODULE__{line: line, col: col, value: String.Chars.to_string(value)}
  end
  def new(value) when is_binary(value) do
    %__MODULE__{line: 0, col: 0, value: value}
  end

  def new({:string, {line, col}, value}, quote_type) when quote_type in [:squote, :dquote] do
    %__MODULE__{line: line, col: col, value: String.Chars.to_string(value), quote_type: quote_type}
  end
  def new({line, col}, value) do
    %__MODULE__{line: line, col: col, value: value}
  end

end

defmodule Piper.Command.Ast.Emoji do

  defstruct [line: nil, col: nil, value: nil]

  def new({:emoji, {line, col}, value}) do
    %__MODULE__{line: line, col: col, value: String.Chars.to_string(value)}
  end

end
