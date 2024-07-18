defmodule Nox.Reader do
  @moduledoc """
  Connect to the NOx box via a serial port, and then read the data stream and hold on to the last value
  """
  use GenServer

  require Logger

  def start_link(%{serial_number: serial_number, address: address}) do
    GenServer.start_link(__MODULE__, %{port_serial: serial_number, address: address},
      name: __MODULE__
    )
  end

  def init(%{port_serial: serial_number, address: address}) do
    {:ok, pid} = Circuits.UART.start_link()

    ports = Circuits.UART.enumerate()

    case find_port(ports, serial_number) do
      {port, _} ->
        Circuits.UART.open(pid, port,
          speed: 9600,
          framing: {Circuits.UART.Framing.Line, separator: "\r"}
        )

        Process.send_after(self(), :ask_for_reading, 1_000)
        {:ok, %{uart: pid, port: port, result: %Nox{}, address: address}}

      _ ->
        Logger.warning("No Nox box found")
        {:ok, %{uart: pid, port: nil, result: %Nox{}, address: address}}
    end
  end

  @doc """
  Helper function to find the right serial port
  given a serial number
  """
  def find_port(ports, serial_number) do
    Enum.find(ports, {"LICOR_PORT", ~c""}, fn {_port, value} ->
      correct_port?(value, serial_number)
    end)
  end

  defp correct_port?(%{serial_number: number}, serial) do
    number == serial
  end

  defp correct_port?(%{}, _serial) do
    false
  end

  defp munge_data(data) do
    # Some of the results have a prefix

    data_list = String.split(data)

    case hd(data_list) do
      "pmt" ->
        parse_float(Enum.at(data_list, 0), Enum.at(data_list, 2))

      "conv" ->
        parse_float(Enum.at(data_list, 0), Enum.at(data_list, 2))

      "no" ->
        parse_float(Enum.at(data_list, 0), Enum.at(data_list, 1))

      "no2" ->
        parse_float(Enum.at(data_list, 0), Enum.at(data_list, 1))

      "nox" ->
        parse_float(Enum.at(data_list, 0), Enum.at(data_list, 1))

      "flow" ->
        parse_float(Enum.at(data_list, 0), Enum.at(data_list, 1))

      _ ->
        {:error, data}
    end
  end

  defp parse_float(compound, value) do
    case Float.parse(value) do
      {number, ""} ->
        {:ok, %{compound: compound, value: number}}

      _ ->
        {:error, %{compound: compound, value: value}}
    end
  end

  def process_data(data, pid) do
    case munge_data(data) do
      {:ok, %{compound: compound, value: value}} ->
        Logger.info("NOx parsing #{inspect(compound)} #{inspect(value)}")

        Process.send(
          pid,
          {:parser, %{datetime: DateTime.utc_now(), compound: compound, value: value}},
          []
        )

      {:error, data} ->
        Logger.info("NOx parsing error #{inspect(data)}")
    end
  end

  defp ask(command) do
    Process.send_after(self(), command, 2_000)
  end

  def port, do: GenServer.call(__MODULE__, :port)

  def current_value, do: GenServer.call(__MODULE__, :current_value)

  def handle_call(:current_value, _from, %{result: result} = state) do
    {:reply, result, state}
  end

  def handle_call(:port, _from, %{port: port} = state) do
    {:reply, port, state}
  end

  def handle_info(:reconnect, state) do
    :ok = Circuits.UART.close(state[:uart])

    case Circuits.UART.open(state[:uart], state[:port],
           speed: 9600,
           framing: {Circuits.UART.Framing.Line, separator: "\r"}
         ) do
      :ok ->
        :ok

      {:error, msg} ->
        Logger.error("NOx reconnect :#{inspect(msg)}")
        Process.send_after(self(), :reconnect, 500)
    end

    {:noreply, state}
  end

  def handle_info({:circuits_uart, port, {:error, msg}}, state) do
    Logger.error("NOx resetting port: #{inspect(msg)}")

    if port == state[:port] do
      Process.send_after(self(), :reconnect, 100)
    end

    {:noreply, state}
  end

  def handle_info({:circuits_uart, port, data}, state) do
    if port == state[:port] do
      Task.start(__MODULE__, :process_data, [data, self()])
      # I should randomly start one of these after a few seconds delay
      [:ask_no, :ask_no2, :ask_nox, :ask_conv, :ask_pmt, :ask_flow]
      |> Enum.random()
      |> ask()
    end

    {:noreply, state}
  end

  def handle_info({:parser, result}, state) do
    result =
      case result[:compound] do
        "no" ->
          Map.put(state[:result], :no, result[:value])

        "no2" ->
          Map.put(state[:result], :no2, result[:value])

        "nox" ->
          Map.put(state[:result], :nox, result[:value])

        "conv" ->
          Map.put(state[:result], :conv_temperature, result[:value])

        "pmt" ->
          Map.put(state[:result], :pmt_temperature, result[:value])

        "flow" ->
          Map.put(state[:result], :flow, result[:value])
      end
      |> Map.put(:datetime, result[:datetime])

    {:noreply, Map.put(state, :result, result)}
  end

  def handle_info(:ask_no, state) do
    Circuits.UART.write(state[:uart], <<state[:address]>> <> "no")
    {:noreply, state}
  end

  def handle_info(:ask_no2, state) do
    Circuits.UART.write(state[:uart], <<state[:address]>> <> "no2")
    {:noreply, state}
  end

  def handle_info(:ask_nox, state) do
    Circuits.UART.write(state[:uart], <<state[:address]>> <> "nox")
    {:noreply, state}
  end

  def handle_info(:ask_for_diagnostic, state) do
    Circuits.UART.write(state[:uart], <<state[:address]>> <> "conv temp")
    Circuits.UART.write(state[:uart], <<state[:address]>> <> "pmt temp")
    Circuits.UART.write(state[:uart], <<state[:address]>> <> "flow")
    {:noreply, state}
  end
end
