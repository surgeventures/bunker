defmodule Bunker.ViolationError do
  @moduledoc """
  Exception raised when a dangerous operation is detected within a transaction.
  """

  defexception [:message]
end
