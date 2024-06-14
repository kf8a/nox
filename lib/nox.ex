defmodule Nox do
  @moduledoc """
  NOx data struct
  """
  defstruct source: :nox, datetime: DateTime.utc_now(), nox: 0, no: 0, no2: 0

  @typedoc """
  A custom type that holds the data from the licor
  """

  @type t :: %Nox{source: :nox, datetime: DateTime, nox: Float, no: Float, no2: Float}
end
