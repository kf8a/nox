defmodule Nox do
  @moduledoc """
  NOx data struct
  """
  defstruct source: :nox,
            datetime: DateTime.utc_now(),
            nox: 0,
            no: 0,
            no2: 0,
            conv_temperature: 0,
            pmt_temperature: 0,
            flow: 0

  @typedoc """
  A custom type that holds the data from the licor
  """

  @type t :: %Nox{
          source: :nox,
          datetime: DateTime,
          nox: Float,
          no: Float,
          no2: Float,
          conv_temperature: Float,
          pmt_temperature: Float,
          flow: Float
        }
end
