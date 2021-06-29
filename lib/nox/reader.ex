defmodule Nox.Reader do
  @moduledoc """
  Connect to the NOx box via a serial port, and then read the data stream and hold on to the last value
  """
  use GenServer

  require Logger

  def start_link(%{serial_number: serial_number, address: address}) do
    GenServer.start_link(__MODULE__, %{port_serial: serial_number, address: address}, name: __MODULE__)
  end

  def init(%{port_serial: serial_number, address: address}) do
    {:ok, pid} = Circuits.UART.start_link

    ports = Circuits.UART.enumerate

    case find_port(ports, serial_number) do
      {port, _} ->
        Circuits.UART.open(pid, port, speed: 9600, framing: {Circuits.UART.Framing.Line, separator: "\r"})
        Process.send_after(self(), :ask_for_reading, 1_000)
        {:ok, %{uart: pid, port: port, result: 0, address: address}}
      _ ->
        Logger.warn "No Nox box found"
        {:ok, %{uart: pid, port: nil, result: 0, address: address}}
    end
  end

  @doc """
  Helper function to find the right serial port
  given a serial number
  """
  def find_port(ports, serial_number) do
    Enum.find(ports, {"LICOR_PORT", ''}, fn({_port, value}) -> correct_port?(value, serial_number) end)
  end

  defp correct_port?(%{serial_number: number}, serial) do
    number ==  serial
  end

  defp correct_port?(%{}, _serial) do
    false
  end

  def  process_data(data, pid) do
    {number_string, _ } = data
                          |> String.split()
                          |> List.pop_at(1)

    case number_string do
      nil ->
        Logger.info "NOx parsing error #{inspect data}"
      not_nil_number_string ->
        case Float.parse(not_nil_number_string) do
          {number, "" } ->
            Process.send(pid, {:parser, number}, [])
          :error ->
            Logger.info "NOx parsing error #{inspect data}"
          _ ->
            Logger.info "NOx parsing error #{inspect data}"
        end
    end
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
    case Circuits.UART.open(state[:uart], state[:port], speed: 9600, framing: {Circuits.UART.Framing.Line, separator: "\r"}) do
      :ok ->
        :ok
      {:error, msg} ->
        Logger.error "NOx reconnect :#{inspect msg}"
        Process.send_after(self(), :reconnect, 500)
    end
    {:noreply, state}
  end

  def handle_info({:circuits_uart, port, {:error, msg}}, state) do
    Logger.error "NOx resetting port: #{inspect msg}"
    if port == state[:port] do
      Process.send_after(self(), :reconnect, 100)
    end
    {:noreply, state}
  end

  def handle_info({:circuits_uart, port, data}, state) do
    if port == state[:port] do
      Task.start(__MODULE__, :process_data, [data, self()])
      Process.send_after(self(), :ask_for_reading, 10_000)
    end
    {:noreply, state}
  end

  def handle_info({:parser, result}, state) do
    # Task.start(Licor.Logger, :save, [result])
    {:noreply, Map.put(state, :result, result)}
  end

  def handle_info(:ask_for_reading, state) do
    Circuits.UART.write(state[:uart],  <<state[:address]>> <> "no")
    {:noreply, state}
  end
end
