defmodule Piper.Ast.Name do

  use Piper.Util.TokenWrapper

  defwrapper [value: :name, token_type: :name]

end
